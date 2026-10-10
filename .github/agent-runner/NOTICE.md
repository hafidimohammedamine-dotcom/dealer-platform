# Third-party content in this folder

- `docker-default-seccomp.json`: Docker's default seccomp profile, copied unchanged from
  https://github.com/moby/moby/blob/v28.3.3/profiles/seccomp/default.json (Moby project, Apache License 2.0,
  https://github.com/moby/moby/blob/v28.3.3/LICENSE). `seccomp.json` is derived from it by `make-seccomp.py`
  (the change is described there); `scripts/check-agent-runner.sh` checks that the derived file matches.
- The GitHub Actions runner (https://github.com/actions/runner, MIT) is downloaded at image build time, pinned by version
  and sha256 in the `Dockerfile`; it is not copied into this repository.
