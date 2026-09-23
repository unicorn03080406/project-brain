# project-brain capture detector. Reads a prompt on stdin, prints one line:
#   context <kind>   the prompt carries project material worth saving (kind: transcript, chat,
#                    email, notes, document)
#   plain <why>      it does not (why: short, typed, code, trace, diff, log, data, shell)
#
# The prompt is split into pasted blocks (VS Code wraps pastes in <pasted_content>) and typed
# text. A pasted block is saved when it reads like prose or a conversation and not like code,
# errors, logs or data. Typed text is saved only when it has strong structure (several speaker
# lines, or email headers), because typed prose is usually an instruction to Claude.
# POSIX awk only: no regex intervals ({n}), no gawk functions.

function reset() {
  n = chars = tech = code = trace = diff = logl = shell = conf = html = csv = 0
  speak = mail = quote = meet = bullets = prose = dates = vtt = timed = 0
  indiff = infence = 0
}

function feature(l,    t, w) {
  if (l ~ /^[[:space:]]*$/) return
  n++; chars += length(l)
  if (l ~ /^[[:space:]]*```/) { infence = !infence; code++; tech++; return }
  if (infence) { code++; tech++; return }

  # --- technical lines ---
  t = 0
  if (l ~ /Traceback \(most recent call last\)/ || l ~ /^[[:space:]]*File "[^"]*", line [0-9]/ ||
      l ~ /^[[:space:]]+at [^ ].*[:(][0-9]/ || l ~ /^[A-Za-z_.]*(Error|Exception)(:| in thread)/ ||
      l ~ /error TS[0-9]/ || l ~ /^(FAILED|ERROR) / || l ~ /AssertionError/) { trace++; t = 1 }
  if (l ~ /^diff --git / || l ~ /^index [0-9a-f]+\.\.[0-9a-f]+/ || l ~ /^@@ .* @@/ ||
      l ~ /^--- a\// || l ~ /^\+\+\+ b\//) { diff++; indiff = 1; t = 1 }
  else if (indiff && l ~ /^[-+ ]/) { diff++; t = 1 }
  if (l ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9:.]+Z? +(INFO|WARN|WARNING|ERROR|DEBUG|TRACE)/ ||
      l ~ /^npm (WARN|ERR)/) { logl++; t = 1 }
  if (l ~ /^\$ / || l ~ /^(On branch|Your branch is|Changes not staged|Changes to be committed|Untracked files|nothing to commit)/ ||
      l ~ /^[[:space:]]+(modified|new file|deleted):/ || l ~ /^added [0-9]+ packages/ ||
      l ~ /^[0-9]+ (failed|passed)/ || l ~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] [A-Z]/) { shell++; t = 1 }
  if (l ~ /^[[:space:]]*[][{}],?[[:space:]]*$/ || l ~ /^[[:space:]]*"[^"]+"[[:space:]]*:/ ||
      l ~ /^[[:space:]]+[a-z_][a-z0-9_-]*:([[:space:]]|$)/ || l ~ /^[a-z_][a-z0-9_.-]*:[[:space:]]*$/ ||
      l ~ /^\[[a-z_.]+\][[:space:]]*$/ || l ~ /^[a-z_][a-z0-9_.-]* = /) { conf++; t = 1 }
  if (l ~ /^[[:space:]]*<\/?[a-z][a-z0-9]*[ >\/]/) { html++; t = 1 }
  if (gsub(/,/, ",", l) >= 3 && l !~ /[.!?] [A-Z]/ && l !~ /^[[:space:]]*[-*]/) { csv++; t = 1 }
  if (l ~ /[;{]$/ || l ~ /^[[:space:]]*}[;)]*$/ ||
      l ~ /^[[:space:]]*(def|class|import|return|elif|except|try:|function|const|let|var|export|interface|public|private|async|await|package|#include) / ||
      l ~ /^[[:space:]]*from [A-Za-z_.]+ import / || l ~ /^[[:space:]]*(if|for|while) .*:$/ ||
      l ~ /^(SELECT|FROM|WHERE|JOIN|ORDER BY|GROUP BY|INSERT|UPDATE|DELETE|CREATE) / ||
      l ~ /^(FROM|WORKDIR|COPY|RUN|CMD|ENV|EXPOSE) / || l ~ /^\.PHONY/ || l ~ /^\t/ ||
      l ~ /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_.]*\(.*\)[[:space:]]*$/ ||
      l ~ /^    .*[=(].*[)=:]/) { code++; t = 1 }
  if (t) { tech++; return }

  # --- context lines ---
  if (l ~ /^[0-9:.]+ --> [0-9:.]+/ || l ~ /^WEBVTT/) { vtt++; return }
  if (l ~ /^\[[0-9][0-9:\/., -]*[AP]?M?\] ?[A-Z][^:]*:/ || l ~ /^\[[0-9][0-9:\/., -]*[AP]?M?\] ?[A-Z][a-z]+( [A-Z][a-z]+)?[[:space:]]*$/ ||
      l ~ /^[A-Z][a-z]+( [A-Z][a-z]+)?( [A-Z][a-z]+)?: [^ ]/ ||
      l ~ /^[A-Z][a-z]+( [A-Z][a-z]+)? +[0-9][0-9]?:[0-9][0-9]( ?[AP]M)?[[:space:]]*$/) speak++
  if (l ~ /^\[[0-9][0-9:\/., -]*[AP]?M?\] ?[A-Z]/) timed++
  if (l ~ /^(Done|Risks?|Next|Notes?|Description|Reporter|Priority|Due|Acceptance|Summary|Status|Decisions?|Action|Terms|Budget|In progress|Hi|Dear|Subject|Update|Question|Answer|Context|Goal|Owner|Topic|Agenda):/) speak = speak > 0 ? speak - 1 : 0
  if (l ~ /^(From|To|Cc|Bcc|Subject|Date|Sent):[[:space:]]/) mail++
  if (l ~ /^On .* wrote:[[:space:]]*$/ || l ~ /^>/) quote++
  if (l ~ /^(Attendees|Participants|Decisions?|Action items|Next (steps|sync|meeting)|Agenda|Minutes|Summary)/ ||
      l ~ /(Decision|Decided|Action|TODO):/) meet++
  if (l ~ /^[[:space:]]*([-*•]|[0-9]+[.)]) /) bullets++
  w = split(l, _w, /[[:space:]]+/)
  if (w >= 8) prose++
  if (l ~ /(19|20)[0-9][0-9]-[01][0-9]-[0-3][0-9]/ || l ~ /[0-3]?[0-9] (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/ ||
      l ~ /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* [0-3]?[0-9]/) dates++
}

# Judge one segment. pasted=1 for a pasted block. Sets VERDICT and KIND.
function judge(pasted,    k) {
  VERDICT = ""; KIND = ""
  if (n == 0) return
  if (tech * 10 >= n * 4) {        # 40% or more technical lines
    k = "code"
    if (trace >= 2) k = "trace"; else if (diff >= 3) k = "diff"; else if (logl >= 2) k = "log"
    else if (shell >= 2) k = "shell"; else if (conf + csv + html > code) k = "data"
    VERDICT = "plain"; KIND = k; return
  }
  k = "document"
  if (meet >= 1 || bullets >= 3) k = "notes"
  if (speak >= 2) k = "chat"
  if (vtt >= 1 || timed >= 3) k = "transcript"
  if (mail >= 2 || (quote >= 2 && mail + meet >= 0 && speak == 0 && bullets == 0 && prose >= 1)) k = "email"
  if (pasted) {
    if ((n >= 3 && chars >= 150) || (chars >= 150 && prose >= 1)) { VERDICT = "context"; KIND = k }
    else { VERDICT = "plain"; KIND = "short" }
    return
  }
  # typed text: only strong structure counts
  if (speak >= 3 || mail >= 2 || vtt >= 1) { VERDICT = "context"; KIND = k }
  else { VERDICT = "plain"; KIND = (n <= 2 && chars < 200) ? "short" : "typed" }
}

function take(pasted) {
  judge(pasted)
  if (VERDICT == "context" && best == "") best = KIND
  if (VERDICT == "plain" && (why == "" || (pasted && !whyp))) { why = KIND; whyp = pasted }
  reset()
}

BEGIN { reset(); best = ""; why = ""; inpaste = 0 }
{
  line = $0
  while (line != "") {
    if (!inpaste) {
      p = index(line, "<pasted_content")
      if (p == 0) { feature(line); line = "" ; break }
      if (p > 1) feature(substr(line, 1, p - 1))
      take(0)                                  # typed text before the paste
      rest = substr(line, p); q = index(rest, ">")
      line = (q > 0) ? substr(rest, q + 1) : ""
      inpaste = 1
    } else {
      p = index(line, "</pasted_content")
      if (p == 0) { feature(line); line = ""; break }
      if (p > 1) feature(substr(line, 1, p - 1))
      take(1)
      rest = substr(line, p); q = index(rest, ">")
      line = (q > 0) ? substr(rest, q + 1) : ""
      inpaste = 0
    }
  }
}
END {
  take(inpaste)
  if (best != "") print "context " best
  else print "plain " (why == "" ? "short" : why)
}
