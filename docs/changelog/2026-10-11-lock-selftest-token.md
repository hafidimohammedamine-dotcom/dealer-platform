# 2026-10-11 - the egress lock's reachability probe uses the job's token

Founder change (`.github/actions/agent-egress-lock/lock.sh`, pins). The lock's self-test checks that api.github.com is
reachable with an anonymous `GET /zen`. Anonymous calls share GitHub's 60-an-hour limit with every other job on the
runner's address, and at 16:51 UTC a review job got a 403 on it and died before Claude started ("allowed host
api.github.com not reachable"). The probe now sends `Authorization: Bearer <GH_TOKEN or GITHUB_TOKEN>` when the job has
one (every Claude job sets `GH_TOKEN`), and stays anonymous otherwise. Tests: the header is sent with a token, absent
without one.
