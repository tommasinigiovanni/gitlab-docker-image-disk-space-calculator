# GitLab Docker Image Disk Space Calculator

A command-line tool to analyze GitLab projects and calculate the total disk space used by Docker images in your GitLab Container Registry.

## Prerequisites

### Required Tools
- `curl` - For making API calls to GitLab
- `jq` - For JSON parsing
- `bc` - For mathematical calculations

### PDF Export Requirements (Optional)
If you plan to use the PDF export feature (`--output pdf`), you'll need:
- `pandoc` - Document converter
- One of the following PDF engines:
  - `weasyprint` (recommended) - Install with: `pip install weasyprint`
  - `pdflatex` - Part of a TeX distribution

Installation examples:
```bash
# macOS
brew install pandoc
pip install weasyprint

# Ubuntu/Debian
sudo apt-get install pandoc python3-weasyprint

# Fedora
sudo dnf install pandoc python3-weasyprint
```

## Configuration

Before running the script, configure the following variables in `bash/gitlab-docker-image-disk-space-calculator.sh`:

```bash
TOKEN="your-gitlab-token"        # Your GitLab token with api/read_registry access
GITLAB_HOST="gitlab.example.com" # Your GitLab server hostname
PER_PAGE=100                     # Number of projects per page (max 100)
LIMIT=0                         # Project limit to process (0 = no limit)
```

## Usage

```bash
./bash/gitlab-docker-image-disk-space-calculator.sh [options]
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--output MODE` | Output format (terminal\|pdf\|csv) | terminal |
| `--file FILE` | Output file path (required for pdf/csv) | - |
| `--include-archived` | Include archived projects | false |
| `--visibility VALUE` | Filter by visibility (private\|internal\|public\|all) | all |
| `--quiet` | Show only final statistics | false |
| `--group GROUP_PATH` | Process only projects in this group | - |
| `--sort-by-size` | Sort projects by size | false |
| `--debug` | Show debug information | false |
| `-h, --help` | Show help message | - |

### Usage Examples

1. Basic analysis with terminal output:
```bash
./bash/gitlab-docker-image-disk-space-calculator.sh
```

2. Export results to CSV file:
```bash
./bash/gitlab-docker-image-disk-space-calculator.sh --output csv --file report.csv
```

3. Generate PDF report:
```bash
./bash/gitlab-docker-image-disk-space-calculator.sh --output pdf --file report.pdf
```

4. Analyze private projects sorted by size:
```bash
./bash/gitlab-docker-image-disk-space-calculator.sh --visibility private --sort-by-size
```

5. Analyze specific group with debug information:
```bash
./bash/gitlab-docker-image-disk-space-calculator.sh --group my-group --debug
```

## Output Formats

### Terminal Output (default)
Displays a real-time analysis with:
- Projects being analyzed
- Docker repositories found
- Tags and their sizes
- Final statistics and summary

Example:
```
🔧 Project: example-project (123)
  📦 Repository: backend
    🏷️ latest - 156.4 MB (156400000 bytes)
    🏷️ v1.0.0 - 155.2 MB (155200000 bytes)

📊 FINAL STATISTICS
----------------------
Projects analyzed: 1
Tags analyzed:     2
Total size used:   0.31 GB / 311.60 MB / 311600000 bytes
```

### CSV Output
When using `--output csv`, generates a CSV file with the following columns:
- Group: Project group path
- Project: Project name
- ProjectID: GitLab project ID
- RepoID: Docker repository ID
- Tag: Image tag name
- SizeBytes: Size in bytes
- SizeMB: Size in megabytes

### PDF Output
When using `--output pdf`, generates a formatted PDF report containing:
- Complete analysis details
- Project information
- Repository details
- Tag sizes
- Final statistics

Note: PDF generation requires either `weasyprint` (recommended) or `pdflatex` to be installed.

## Troubleshooting

If you encounter any issues:

1. Missing Dependencies
   - For PDF output, ensure you have both `pandoc` and a PDF engine installed
   - For basic functionality, verify `curl`, `jq`, and `bc` are installed

2. API Issues
   - Verify your GitLab token has the required permissions (api/read_registry)
   - Use the `--debug` option to see detailed API call information
   - Check your connection to the GitLab server

3. PDF Generation Issues
   - Ensure you have either `weasyprint` or `pdflatex` installed
   - Try installing `weasyprint` using pip: `pip install weasyprint`
   - Check if `pandoc` is correctly installed

4. Performance Issues
   - Check GitLab API rate limits if you're analyzing many projects
   - Use the `LIMIT` configuration to process fewer projects during testing

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - Feel free to use this tool in your projects.


