# config.sh

Manage .env configuration files for Shell

## Install

### Using [bpkg (Bash Package Manager)](https://bpkg.sh/)

```bash
bpkg install jeremfg/config.sh
```

or

```bash
bpkg install -g jeremfg/config.sh
```

NOTE: bpkg itself can easily be installed by calling
`curl -sLo- https://get.bpkg.sh | bash`

In the first case, the library is installed local to your project.
You will need to `source deps/config.sh/src/config.sh`.
In the second case, the library is installed globally.
You will need to `source ~/.local/lib/config.sh`.

## Features

Provides the following functions:

```bash
config_load()
config_save()
```

Usage example:

```bash
# Assuming a BPKG global installation
source ~/.local/lib/config.sh

config_load "~/my_cool_config.env"
config_save "~/my_cool_config.env" "KEY_TO_SAVE" "VALUE_TO_SAVE"
```

### SOPS encryption

When calling `config_save`, an existing key will be updated with the new value
if it exists or a new entry will be created to store the value.
If passing an empty value, the key will be deleted from the file.

The `<file>` can be encrypted upon calling `config_load`.
Likewise, if the existing file is encrypted upon calling `config_save`,
the changes will be encrypted back during save to disk,
letting SOPS use environment variables to determine how the file
should be encrypted.

### Special values

`config.sh` supports special values and will perform replacement
upon `config_load` if these strings are detected

<!-- markdownlint-disable MD013 -->
| Special Value | Description |
| ------------- | ----------- |
| @GIT_ROOT@    | Path to the parent repository root (equivalent to `git rev-parse --show-superproject-working-tree`). This is relative to the CWD. |
| | |
<!-- markdownlint-enable MD013 -->

These special values are mostly useful to create project-relative configuraitons

## Setup for developers

Once you've checked out this repository call the following:

```bash
./tool/setup
```

### Release

To create a release, call

```bash
./tool_release <version>
```

Where `<version>` is a semantic version 2.0.0 version number
