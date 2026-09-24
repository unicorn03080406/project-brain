# Read a hook's JSON input (needs json.awk loaded first). Prints shell assignments for eval:
# SID, SRC, IN_CWD, TRANSCRIPT, PROMPT_ID, SCRATCH, PLEN (prompt length in characters).
# Writes the prompt to the file named by -v pf only when it is long enough to be worth
# checking for capture (-v min), so short prompts never touch the disk.
function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
{ all = all $0 "\n" }
END {
  p = jget(all, "prompt")
  printf "SID=%s\nSRC=%s\nIN_CWD=%s\nTRANSCRIPT=%s\nPROMPT_ID=%s\nSCRATCH=%s\nPLEN=%d\n",
    q(jget(all, "session_id")), q(jget(all, "source")), q(jget(all, "cwd")),
    q(jget(all, "transcript_path")), q(jget(all, "prompt_id")), q(jget(all, "scratchpad_dir")), length(p)
  if (pf != "" && length(p) >= min) printf "%s", p > pf
}
