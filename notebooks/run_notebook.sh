#!/bin/bash
# ================================================================
# Headless Notebook Runner (Background + Stable Logging)
# Usage: ./run_notebook.sh <notebook.ipynb> [conda_env] [kernel_name]
# ================================================================

set -u

if [ $# -lt 1 ]; then
  echo "Usage: ./run_notebook.sh <notebook.ipynb> [conda_env] [kernel_name]"
  exit 1
fi

NOTEBOOK_INPUT="$1"
CONDA_ENV="${2:-alpha}"
KERNEL_NAME="${3:-python3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

if [ ! -f "$NOTEBOOK_INPUT" ]; then
  echo "Error: File '$NOTEBOOK_INPUT' not found (cwd: $SCRIPT_DIR)."
  exit 1
fi

NOTEBOOK="$(basename "$NOTEBOOK_INPUT")"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

BASENAME=$(basename "$NOTEBOOK" .ipynb)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_NB="${LOG_DIR}/executed_${BASENAME}_${TIMESTAMP}.ipynb"
LOGFILE="${LOG_DIR}/${BASENAME}_${TIMESTAMP}.md"
NOHUP_LOG="${LOG_DIR}/${BASENAME}_${TIMESTAMP}_nohup.log"

echo "----------------------------------------------------------"
echo "Execution started"
echo "Notebook:      $NOTEBOOK"
echo "Conda env:     $CONDA_ENV"
echo "Kernel name:   $KERNEL_NAME"
echo "Markdown log:  $LOGFILE"
echo "Live nohup:    $NOHUP_LOG"
echo "----------------------------------------------------------"

# FIX 1: Export SCRIPT_DIR so the inner subshell knows exactly where to execute.
export NOTEBOOK CONDA_ENV KERNEL_NAME OUTPUT_NB LOGFILE NOHUP_LOG SCRIPT_DIR

nohup bash -lc '
  # Move log initialization to the very top so we immediately capture the file
  : > "$NOHUP_LOG"
  : > "$LOGFILE"

  # FIX 2: Explicitly change back to the script directory. (bash -l starts in $HOME!)
  cd "$SCRIPT_DIR" || exit 1

  # FIX 3: Turn off strict unbound variables for Conda. Conda init scripts will crash otherwise.
  set +u
  if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"
  fi
  set -u # Turn strict mode back on safely

  log_info() {
    local msg="$1"
    echo "$msg" | tee -a "$NOHUP_LOG" >> "$LOGFILE"
  }

  echo "# Execution Log: $NOTEBOOK" >> "$LOGFILE"
  echo "Started at: $(date)" >> "$LOGFILE"
  echo "Conda env: $CONDA_ENV" >> "$LOGFILE"
  echo "Kernel: $KERNEL_NAME" >> "$LOGFILE"
  echo "---" >> "$LOGFILE"

  log_info "[INFO] Started at: $(date)"
  log_info "[INFO] Notebook: $NOTEBOOK"
  log_info "[INFO] Conda env: $CONDA_ENV"
  log_info "[INFO] Kernel: $KERNEL_NAME"
  log_info "[INFO] Output notebook: $OUTPUT_NB"
  log_info "[INFO] Executing notebook..."

  if command -v stdbuf >/dev/null 2>&1; then
    stdbuf -oL -eL jupyter nbconvert --to notebook --execute \
      --ExecutePreprocessor.kernel_name="$KERNEL_NAME" \
      --ExecutePreprocessor.timeout=-1 \
      --output "$OUTPUT_NB" "$NOTEBOOK" 2>&1 | tee -a "$NOHUP_LOG" >> "$LOGFILE"
    EXIT_CODE=${PIPESTATUS[0]}
  else
    jupyter nbconvert --to notebook --execute \
      --ExecutePreprocessor.kernel_name="$KERNEL_NAME" \
      --ExecutePreprocessor.timeout=-1 \
      --output "$OUTPUT_NB" "$NOTEBOOK" 2>&1 | tee -a "$NOHUP_LOG" >> "$LOGFILE"
    EXIT_CODE=${PIPESTATUS[0]}
  fi

  log_info "[INFO] Notebook execution exit code: $EXIT_CODE"

  if [ "$EXIT_CODE" -eq 0 ]; then
    log_info "[INFO] Rendering executed notebook to markdown log..."
    jupyter nbconvert --to markdown "$OUTPUT_NB" --stdout >> "$LOGFILE" 2>> "$NOHUP_LOG"
    echo "---" >> "$LOGFILE"
    echo "Finished at: $(date)" >> "$LOGFILE"
    echo "Status: success" >> "$LOGFILE"
    log_info "[INFO] Completed successfully."
  else
    echo "---" >> "$LOGFILE"
    echo "Finished at: $(date)" >> "$LOGFILE"
    echo "Status: failed (see $NOHUP_LOG)" >> "$LOGFILE"
    log_info "[ERROR] Notebook execution failed."
  fi
' >/dev/null 2>&1 &

PID=$!

echo "Process detached with PID: $PID"
echo "Monitor live progress: tail -f $NOHUP_LOG"
echo "Final notebook output: $OUTPUT_NB"
echo "----------------------------------------------------------"