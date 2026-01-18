# Fix frogml API Usage for Model Download

## Overview
The `artifactory_helper.py` is using incorrect `frogml` API methods that don't exist in version 1.2.29. The correct method is `frogml.files.load_model()` instead of `download_model()` or `get_model_version()`.

## Problem
- `frogml.files.download_model()` doesn't exist
- `frogml.files.get_model_version()` doesn't exist
- Error: `AttributeError: module 'frogml.sdk.model_version.files' has no attribute 'get_model_version'`

## Solution
Replace with the correct `frogml` API methods:
- Use `frogml.files.load_model()` for downloading models
- Use `frogml.files.get_model_info()` for getting model metadata (if needed)

## Changes

### 1. Fix `download_model_from_ml_repository` in [`src/utils/artifactory_helper.py`](src/utils/artifactory_helper.py)

**Location:** Lines 277-297

**Current (incorrect):**
```python
try:
    # Try using frogml.files.download_model() first
    try:
        frogml.files.download_model(
            repository=ml_repo_name,
            model_name=model_name,
            version=version,
            destination_path=download_path
        )
    except AttributeError:
        # If download_model doesn't exist, try get_model_version().download()
        model_version = frogml.files.get_model_version(
            repository=ml_repo_name,
            model_name=model_name,
            version=version
        )
        if filename:
            target_path = os.path.join(download_path, filename)
        else:
            target_path = download_path
        model_version.download(target_path)
```

**Change to:**
```python
try:
    # Use frogml.files.load_model() - the correct API method
    target_path = download_path
    if filename:
        target_path = os.path.join(download_path, filename)
        # Ensure parent directory exists
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    frogml.files.load_model(
        repository=ml_repo_name,
        model_name=model_name,
        version=version,
        target_path=target_path
    )
```

### 2. Fix `verify_model_upload` in [`src/utils/artifactory_helper.py`](src/utils/artifactory_helper.py)

**Location:** Lines 228-235

**Current (incorrect):**
```python
# Use frogml.files.get_model_version() to check if model exists
model_version = frogml.files.get_model_version(
    repository=ml_repo_name,
    model_name=model_name,
    version=version
)
# If we can get the model version, it exists
return model_version is not None
```

**Change to:**
```python
# Use frogml.files.get_model_info() to check if model exists
model_info = frogml.files.get_model_info(
    repository=ml_repo_name,
    model_name=model_name,
    version=version
)
# If we can get the model info, it exists
return model_info is not None
```

### 3. Update docstring in `download_model_from_ml_repository`

**Location:** Line 254

**Current:**
```python
Uses frogml.files.download_model() or frogml.files.get_model_version().download().
```

**Change to:**
```python
Uses frogml.files.load_model().
```
