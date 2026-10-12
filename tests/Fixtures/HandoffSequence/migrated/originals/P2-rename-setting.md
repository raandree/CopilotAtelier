# Rename the timeout setting

Run this after the retry prompt has finished.

Rename the Timeout setting to TimeoutSeconds everywhere it is read, and keep the
old name working for one version with a warning.

## Steps

1. Add the new name and map the old one to it.
2. Update the tests and the sample configuration.

## Tests

The configuration tests pass.

Run the tests before you commit and do not skip a failing test.
