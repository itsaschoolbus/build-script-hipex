# CI Bot Script

![Bash Shell](https://img.shields.io/badge/Shell-Bash-blue?style=for-the-badge&logo=gnu-bash)

A powerful and customizable Bash script for building Android ROMs with continuous integration (CI) support. This script automates the entire process, from syncing sources to uploading the final build and sending notifications to Telegram.

## Features

- **Automated Builds**: Fully automates the ROM building process.
- **Telegram Integration**: Sends real-time notifications for build status, progress, and completion.
- **Customizable Configuration**: Easily configure build options, Telegram settings, and API keys in a separate `config.env` file.
- **Interactive Setup**: Prompts for the device codename if not specified in the configuration.
- **Error Handling**: Automatically detects build failures and sends detailed error logs to a designated Telegram chat.
- **File Uploading**: Uploads build artifacts to PixelDrain and includes download links in the final notification.

## Prerequisites

Before using this script, ensure you have the following dependencies installed:

- `bash`
- `curl`
- `tput`
- `nproc`
- `repo`

## Configuration

1.  **Fork the repository** and clone it to your local machine.
2.  **Create a `config.env` file** in the root of the project by copying the example:

    ```bash
    cp config.env.example config.env
    ```

3.  **Fill in the required variables** in `config.env`:

    - `CONFIG_DEVICE`: The device codename (e.g., `lancelot`). If left empty, the script will prompt for it.
    - `CONFIG_TARGET`: The build target (e.g., `bacon`).
    - `CONFIG_OFFICIAL_FLAG`: The flag to export for an official build.
    - `CONFIG_CHATID`: Your Telegram channel/group chat ID.
    - `CONFIG_BOT_TOKEN`: Your Telegram bot token.
    - `CONFIG_ERROR_CHATID`: (Optional) A separate chat ID for error logs.
    - `CONFIG_PDUP_API`: Your PixelDrain API key.
    - `POWEROFF`: Set to `true` to power off the server after the build is complete.

## Usage

To run the script, use the following command:

```bash
bash ci_bot.sh [OPTIONS]
```

### Options

- `-s`, `--sync`: Sync sources before building.
- `-c`, `--clean`: Clean the build directory before compilation.
- `-o`, `--official`: Build the official variant.
- `-h`, `--help`: Show the help message.

### Example

To sync sources, clean the output directory, and start a build, run:

```bash
bash ci_bot.sh -s -c
```

## Contributing

Contributions are welcome! If you have any suggestions or improvements, feel free to open an issue or submit a pull request.
