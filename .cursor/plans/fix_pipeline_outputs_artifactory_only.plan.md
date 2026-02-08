# Fix Pipeline Outputs and Batch Inference Artifactory-Only

## Overview
Fix the pipeline return statements to use specific output references, and ensure batch inference downloads models exclusively from Artifactory with proper error handling.

## Changes

### 1. Fix `training_pipeline` return in [`pipeline/training_pipeline.py`](pipeline/training_pipeline.py)

**Location:** Line 118

**Current:**
```python
return {"train_outputs": train_step.outputs}
```

**Change to:**
```python
return {
    "model": train_step.outputs.model,
    "metrics": train_step.outputs.metrics,
    "metadata": train_step.outputs.metadata
}
```

This matches the outputs defined in the `train_cmd` command (lines 106-110).

### 2. Fix `training_with_inference_pipeline` return in [`pipeline/training_pipeline.py`](pipeline/training_pipeline.py)

**Location:** Lines 198-201

**Current:**
```python
return {
    "train_outputs": train_step.outputs,
    "inference_results": inference_step.outputs
}
```

**Change to:**
```python
return {
    "train_outputs": train_step.outputs.outputs,
    "inference_results": inference_step.outputs.inference_results
}
```

This references the specific output names defined in the command components (line 170 and line 190).

### 3. Fix batch inference to require Artifactory in [`src/batch_inference.py`](src/batch_inference.py)

**Location:** Lines 177-193

**Current:** Has try/except but doesn't handle failure properly - `model` becomes undefined if Artifactory fails.

**Change to:**
```python
# Load model from Artifactory (required - no fallback)
if not all([
    os.environ.get('ARTIFACTORY_HOST'),
    os.environ.get('AZURE_KEY_VAULT_NAME'),
    os.environ.get('ARTIFACTORY_ML_REPO')
]):
    raise ValueError(
        "Missing required environment variables for Artifactory: "
        "ARTIFACTORY_HOST, AZURE_KEY_VAULT_NAME, ARTIFACTORY_ML_REPO"
    )

try:
    model, label_map, reverse_label_map = load_model_from_artifactory()
    logger.info("✓ Model loaded from Artifactory")
except Exception as e:
    logger.error(f"Failed to load model from Artifactory: {e}")
    raise RuntimeError(f"Cannot proceed without model from Artifactory: {e}") from e
```

This ensures:
- Environment variables are checked first
- If Artifactory download fails, the script fails with a clear error
- No undefined variable issues

### 4. Remove unused `load_model_from_local` function in [`src/batch_inference.py`](src/batch_inference.py)

**Location:** Lines 73-87 (approximately)

Remove the entire `load_model_from_local` function since it's no longer used.
