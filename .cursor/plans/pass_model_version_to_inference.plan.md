# Pass Model Version from Training to Batch Inference

## Overview
The batch inference step is using "latest" as the model version instead of the actual version that was uploaded during training. The training step generates a version (e.g., `v20260117065618`) and saves it in `metadata.json`, but the inference step doesn't read it.

## Problem
- Training step generates version: `datetime.utcnow().strftime('v%Y%m%d%H%M%S')` and saves in `metadata.json`
- Training step uploads model to Artifactory with that specific version
- Batch inference step defaults to `'latest'` when `MODEL_VERSION` env var is not set
- This causes 404 error because "latest" doesn't exist in Artifactory

## Solution
Read the model version from the `metadata.json` file in the training step's output directory (which is passed as `model_outputs` input to the inference step).

## Changes

### 1. Update `batch_inference.py` to read version from metadata

**Location:** `load_model_from_artifactory()` function and `run_batch_inference()` function

**Current:** 
```python
model_version = os.environ.get('MODEL_VERSION', 'latest')
```

**Change to:**
- Add a function to read version from metadata.json in the model_outputs directory
- Use that version instead of defaulting to 'latest'
- Fall back to environment variable if metadata file not found

### 2. Update pipeline to pass model_outputs path to batch inference

**Location:** `training_with_inference_pipeline()` in `pipeline/training_pipeline.py`

**Current:** The inference step receives `model_outputs` as input but doesn't use it to read metadata.

**Change to:**
- Update the batch inference command to accept `--model_outputs` argument
- Pass the input path: `--model_outputs ${{inputs.model_outputs}}`
- Update `batch_inference.py` to read metadata from that path

### 3. Update `batch_inference.py` main function

**Location:** `if __name__ == "__main__"` section

**Current:** Only accepts `--inference_results` argument

**Change to:**
- Add `--model_outputs` argument
- Read metadata.json from that path to get the version
- Pass version to `load_model_from_artifactory()` function
