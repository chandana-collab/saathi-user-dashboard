You are running unattended to refresh Chandana's Saathi dashboard. Do only the steps below; publish nothing else, contact no one.

Dashboard: https://claude.ai/artifact/73fBDwkrxDqgsqgADWM9ce
Fresh files (already computed locally):
- C:\Users\jeeva\ChandanaOS\data\saathi\out\saathi-users.csv        -> dataset "users"
- C:\Users\jeeva\ChandanaOS\data\saathi\out\saathi-mip-sessions.csv -> dataset "mipSessions"
- C:\Users\jeeva\ChandanaOS\data\saathi\out\saathi-coverage.csv     -> dataset "coverage"

Steps:
1. ArtifactData get collection "datasets", doc_ids users, mipSessions, coverage. Note each version and its current source.url (old asset id = the 32 hex chars after /_blob/).
2. Upload each fresh CSV with the Artifact tool (publish, url above, asset: true, file_path = the CSV; one call per file).
3. One ArtifactData batch: for each of the three datasets an "update" with if_version, setting
   source.url to the new /_blob/ url, updated = {at: <now UTC ISO>, by: "Scheduled sync of all tabs in the Saathi conversation data log"},
   edit = {via: "claude", at: <now UTC ISO>}. Change nothing else. Do not touch files/index.html.
4. After the batch succeeds, delete each OLD asset id from step 1 (Artifact action delete, path = old id), only if it differs from the new one.
5. If every step succeeded, end your reply with the single line: SYNC_OK
   If anything failed, say what failed and do not print SYNC_OK.
