## What / why

<!-- Link the issue if there is one. Conventional commit subject, please
     (fix:/feat:/docs:/chore:) — history is read straight off `main`. -->

## Verification

Run the block from AGENTS.md before pushing:

```bash
bash -n setup_env.sh run_server.sh quickstart.sh build_engine.sh
bash tests/test_run_server_args.sh
bash tests/test_cache_profile.sh
bash tests/test_build_engine_flags.sh
```

- [ ] Scripts parse and the three test suites pass
- [ ] Ran the affected path (profile / command / model):
- [ ] Benchmark numbers, if any, are measured on this hardware and labelled as such

## Follow-ups

<!-- Anything you deliberately left out, and whether it needs an issue. -->
