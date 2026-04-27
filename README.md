## Temporal Fusion Nexus: A task-agnostic multi-modal embedding model for clinical narratives and irregular time series in post-kidney transplant care. 

Summary: Multimodal modeling for kidney transplant patients on the NephroCAGE cohort. The code fuses irregular time-series vitals, static donor/recipient attributes, and free-text clinical notes to forecast graft loss, rejection, and mortality across multiple horizons.

## Repository Map
- `src/preprocessing.py`: load raw NephroCAGE files, clean/merge static tables, build time-series (vitals, labs, meds), embed notes, and assemble the PyTorch `NephroCAGEDataset` plus `collate_fn`.
- `src/models.py`: time-aware LSTM encoder, temporal self-attention, static fusion, notes cross-attention, and a VAE variant.
- `src/utils.py`: representation diagnostics (mutual information, decorrelation) and lightweight feature decoders.
- `notebooks/`: preprocessing, training (classification + VAE), calibration, clustering, interpretation, visualizations, and study analysis.
- `data/results/`: precomputed metrics/plots (e.g., `final_res.json`, `temporal_attention.json`, `shap.json`); raw data are not included.

## Setup
1. Python 3.10 recommended.
2. Create an environment and install dependencies:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
3. Notes encoder downloads `thenlper/gte-large` from Hugging Face; ensure access or pre-cache via `HF_HOME`.
4. GPU is recommended for training and note embedding.

## Data
NephroCAGE is not available publicly. We ustilised NephroCAGE v1 raw files under `data/v1/` using the filenames:
- 1_BAseline_parameter_fertig2_HLA_Pirche_final.xlsx
- 2_donoparameter_final.xlsx
- 4_exams.csv
- 5 Biopsy_patho_kreuz_extensive.xlsx
- 6 Lab_cohort.csv
- 7_clinical_assessment.csv
- 8_Medikation.csv
- 9_Hospitalization.xlsx
- 10_HLA-DSA_timecourse.xlsx

## Preprocessing Workflow
- Use notebooks (`preprocessing_static.ipynb`, `preprocessing_vitals.ipynb`, `preprocessing_medication.ipynb`, `preprocessing_notes.ipynb`) for exploratory runs, or call helpers in `src/preprocessing.py`:
  - `get_dfs(project_path)` loads all raw tables.
  - `create_static_df`, `create_vitals_df`, `create_medication_df`, `create_notes_df` clean each modality.
  - `create_ts_data` merges vitals/labs/meds, computes eGFR, and aligns timelines.
  - `get_valid_patient_ids`, `split_patient_ids`, and `create_dataset_splits` build patient-level train/val/test splits before fitting preprocessors.
  - `NephroCAGEDataset` packages static + time-series + note embeddings with masks and can reuse train-fitted preprocessing artifacts for val/test; `collate_fn` pads variable-length batches.
- `CONFIG` in `src/config.py` lists static categorical/numerical features, time-series features, padding value, and model dimensions.

## Modeling Overview
- Time-series backbone: `TimeAwareLSTM` (elapsed-time aware) with optional temporal self-attention (`TimeAwareAttentionEncoder`) or a vanilla LSTM encoder.
- Static fusion: `StaticEncoder` embeds categorical + scaled numerical features and injects them into hidden states.
- Notes fusion: `NotesEncoder` (GTE-large) with cross-attention for time steps to attend to note embeddings.
- Heads: `MultiModal` for deterministic forecasting; `MultiModalVAE` for variational modeling; `SimpleMLP` for lightweight classification.

## Training and Evaluation
- Main flows: `training.ipynb` (multimodal forecasting/classification) and `vae_training.ipynb` (generative).
- Extras: `classification.ipynb` + `classification_calibration.ipynb` (risk and calibration), `clustering.ipynb` (latent analysis), `interpret.ipynb` (feature importance/SHAP), `visualizations.ipynb` + `results.ipynb` (plots/metrics), `study.ipynb` (user study summaries).
- Aggregated AUROCs by horizon are stored in `data/results/final_res.json`; other experiment variants are in `data/results/*.json`.

## Repro Tips
- Cache Hugging Face models before running note-heavy notebooks.
- Run preprocessing steps first so downstream notebooks can load cleaned arrays/embeddings.
- When adding features, update `CONFIG` and preprocessing so shapes stay aligned across dataset, encoders, and heads.
