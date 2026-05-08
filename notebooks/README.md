# Notebook Execution Guide

Pipeline order for reproducing results end-to-end. Each step depends on the previous one.

---

## Some general info: 

1. Model checkpointing is used in training.ipynb and classification.ipynb. The best-performing fold's model is saved for each task/horizon combo. The calibration notebook loads these checkpoints to evaluate and calibrate the probabilities.

2. Training is done on 90% dataset with 10% val used for model checkpointing. Classification uses 80% train, 20% test splits.

3. Training is a self-supervised next-timestep prediction task. Classification heads are trained separately on frozen backbone representations.

## Metrics:

### Original Paper (5 Fold CV):


| Event | 30-day | 90-day | 180-day |
|---|---|---|---|
| **GraftLoss** | 0.962 ± 0.006 | 0.965 ± 0.011 | 0.962 ± 0.009 |
| **Rejection** | 0.844 ± 0.012 | 0.847 ± 0.013 | 0.849 ± 0.010 |
| **Mortality** | 0.860 ± 0.010 | 0.859 ± 0.011 | 0.851 ± 0.013 |

### This code (5 Fold CV - 2782 patients in Pool A):

*CV Mean AUC (averaged across 5 folds):*

| Event | 30-day | 90-day | 180-day |
|---|---|---|---|
| **GraftLoss** | 0.9480 ± 0.0201 | 0.9196 ± 0.0321 | 0.9027 ± 0.0247 |
| **Rejection** | 0.8919 ± 0.0203 | 0.8691 ± 0.0243 | 0.8528 ± 0.0345 |
| **Mortality** | 0.9241 ± 0.0157 | 0.9088 ± 0.0102 | 0.8741 ± 0.0124 |


## Step 0: Environment Setup

```bash
conda create -n alpha python=3.10
conda activate alpha
pip install -r requirements.txt
```

Run any notebook headless:
```bash
cd notebooks
./run_notebook.sh <notebook.ipynb>
```

---

## Step 1: Finetune Notes Language Model

**Notebook:** `generate_embeddings/finetune_gte.ipynb`

Finetunes a GTE model with SimCSE on German+English medical notes.

**Output:** `models/med-gte-simcse-ger/`

---

## Step 2: Generate Note Embeddings

**Notebook:** `generate_embeddings/create_notes_embeddings.ipynb`

Encodes all patient notes into dense vectors using the finetuned model from Step 1.

**Output:** `data/embeddings/emb_med_gte_simcse_en_ger.npy`


---

## Step 3: Pool Assignment

**IMPORTANT:**  This step is only important if you want to split your data into different pool according to the criteria. If you want to use the same pool assignment as before, you can skip this step use the complete dataset in the training and classification notebooks.

**Notebook:** `dataset_pool_assignment.ipynb`

Splits the full patient cohort into Pool A (training/evaluation) and Pool B (held out for future use). Pool C is small pool for testing but you can edit this data split logic as you see fit.

**Output:** `data/splits/pool_assignments.json`
- Pool A: 2,782 patients
- Pool B: 550 patients
- Pool C: 50 patients

---

## Step 4: Train Backbone (Self-Supervised)

**Notebook:** `training.ipynb`

Trains the TimeAwareAttentionEncoder + MultiModal backbone on next-timestep prediction (MSE loss). Uses Pool A patients with a 90/10 train/val split. No labels used — purely self-supervised.

**Config:**
- Encoder: `TimeAwareAttentionEncoder(use_temporal_attention=True)`
- `use_static=True`, `use_notes=True`, `require_notes=True`
- 90/10 split: `data/splits/global_split_pool_a_9010.json`
- lr=0.0003, batch_size=16, predict_steps_ahead=1
- Epochs: 30 (best checkpoint saved)

**IMPORTANT:** Modify the `global_split_pool_a_9010.json` file if you want to change the train/val split. The training notebook will automatically use whatever split is defined in that file.

**Output:** `models/backbone_poola_9010_best.pt`

---

## Step 5: Train Classification Heads

**Notebook:** `classification.ipynb`

**IMPORTANT:** This notebook takes a lot of time since I trained on 30 epochs with 5 folds. You can run_notebook.sh to run headless or modify the code to train for fewer epochs or fewer folds for testing.

Freezes the backbone from Step 4, extracts 512-dim hidden representations for all Pool A patients, then trains SimpleMLP classifier heads using 5-fold StratifiedGroupKFold CV (patient-aware splits, no leakage).

**Config:**
- Backbone: frozen `backbone_poola_9010_best.pt`
- Representation extraction: min_history=90 days, max_days=720, 100 samples/patient (uniform)
- Classifier: SimpleMLP (512 → 128 → 1)
- 5-fold StratifiedGroupKFold, 15 epochs per fold, dynamic pos_weight
- Best fold saved per task

**Tasks:** GraftLoss, Rejection, Mortality × horizons 30, 90, 180 days = 9 models

**Output:** `models/run-16-final/` containing:
- `GraftLoss@{30,90,180}_clf.pth`
- `Rejection@{30,90,180}_clf.pth`
- `Mortality@{30,90,180}_clf.pth`

Each checkpoint contains: `model_state_dict`, `best_fold`, `cv_metrics`, `fold_metrics`

---

## Post-Training Notebooks

These use the trained backbone + heads. Run in any order.

### Calibration Analysis

**Notebook:** `misc/classification_calibration.ipynb`

Evaluates probability calibration of the MLP heads from `run-16-final/`. Computes calibration curves, Brier scores, Platt scaling, and isotonic regression for all 9 task/horizon combos. Also includes threshold analysis for clinical operating points.

**Output:** Calibration and threshold plots in `plots/`

### Interpretation (SHAP)

**Notebook:** `misc/interpret.ipynb`

SHAP-based feature importance and temporal analysis on the trained model.

### Dataset Statistics

**Notebook:** `results.ipynb`

Dataset statistics, cohort summaries, and outcome distributions.

### Visualizations

**Notebook:** `misc/visualizations.ipynb`

t-SNE, patient trajectory plots, and other visual analyses.

### Clustering

**Notebook:** `misc/clustering.ipynb`

Patient clustering on learned representations.

---

## Preprocessing Notebooks (Reference Only)

These are exploratory/development notebooks for understanding the raw data. The preprocessing pipeline is implemented in `src/preprocessing.py` and called directly by the training/classification notebooks.

- `preprocessing/preprocessing_static.ipynb` — static patient features
- `preprocessing/preprocessing_vitals.ipynb` — vitals and lab values
- `preprocessing/preprocessing_medication.ipynb` — medication data
- `preprocessing/preprocessing_notes.ipynb` — clinical notes

---

## Dependency Chain

```
models/med-gte-simcse-ger/           (Step 1: finetuned language model)
    → data/embeddings/emb_*.npy      (Step 2: note embeddings)
    → data/splits/pool_assignments.json  (Step 3: pool assignment)
    → data/splits/global_split_pool_a_9010.json  (Step 4: backbone split)
    → models/backbone_poola_9010_best.pt         (Step 4: trained backbone)
    → models/run-16-final/*_clf.pth              (Step 5: classifier heads)
    → misc notebooks (calibration, interpretation, visualization)
```
