---
layout: post
toc: true
title: "ML Data Operations: Deep Dive into Data-Centric ML Infrastructure"
date: 2026-06-27
permalink: /references/ml-data-operations-data-centric-ml-infrastructure/
noindex: true
sitemap: false
categories: [learnings]
tags: [markdown, machine-learning, data-operations, data-engineering, mlops, multimodal]
---

# ML Data Operations: Deep Dive into Data-Centric ML Infrastructure

## Introduction

While ML infrastructure focuses on features, models, and serving, **data operations** is about the data itself: acquiring it, annotating it, ensuring its quality, augmenting it synthetically, and managing it at petabyte scale. This guide covers the data-centric aspects of ML systems, with emphasis on multimodal data (vision, audio, text) at billion-scale.

Related post: [Batch, Streaming, and Merged Views in ML Data Operations]({% post_url 2026-06-27-batch-streaming-merged-views-ml-data-operations %}) explains how the batch lane, streaming lane, and merged serving/training view fit together.

---

## 1. Data Annotation Workflows

**Purpose**: Transform raw data into labeled training data through manual, semi-automated, or fully automated annotation pipelines.

### 1.1 Annotation Types

**Classification labels**:
```json
{
  "image_id": "img_12345",
  "label": "cat",
  "confidence": 0.95,
  "annotator_id": "user_789",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Bounding boxes** (object detection):
```json
{
  "image_id": "img_12345",
  "annotations": [
    {
      "label": "cat",
      "bbox": [100, 150, 300, 400],  // [x_min, y_min, x_max, y_max]
      "confidence": 0.92
    }
  ]
}
```

**Segmentation masks** (instance/semantic segmentation):
```json
{
  "image_id": "img_12345",
  "mask_path": "s3://annotations/img_12345_mask.png",
  "classes": {
    "1": "cat",
    "2": "dog",
    "3": "background"
  }
}
```

**Keypoints** (pose estimation):
```json
{
  "image_id": "img_12345",
  "keypoints": [
    {"label": "nose", "x": 150, "y": 200, "visibility": 2},
    {"label": "left_eye", "x": 140, "y": 190, "visibility": 2}
  ]
}
```

**Text annotations** (NLP):
```json
{
  "text_id": "txt_67890",
  "entities": [
    {"text": "Apple", "label": "ORG", "start": 0, "end": 5},
    {"text": "Cupertino", "label": "LOC", "start": 15, "end": 24}
  ]
}
```

### 1.2 Annotation Tools

**Open-source**:
- **Label Studio**: Flexible, supports multiple annotation types
- **CVAT**: Computer vision focused, video annotation
- **Labelbox**: Enterprise-grade, collaboration features

**Commercial**:
- **Scale AI**: Managed annotation service, high quality
- **Labelbox**: Enterprise platform with ML-assisted labeling
- **Supervisely**: Computer vision focused

**Custom tools** (Apple-scale):
```python
# Custom annotation interface
class AnnotationTool:
    def __init__(self, schema: AnnotationSchema):
        self.schema = schema
        self.queue = AnnotationQueue()
    
    def load_next_image(self) -> Image:
        # Priority-based sampling
        return self.queue.get_next(
            strategy="uncertainty_sampling",  # Prioritize uncertain examples
            model_version="v2.3"
        )
    
    def save_annotation(self, annotation: Annotation):
        # Validate against schema
        self.schema.validate(annotation)
        # Store with metadata
        self.store.save(annotation, metadata={
            "annotator_id": self.current_user,
            "time_spent": self.timer.elapsed(),
            "model_assistance": self.model_predictions
        })
```

### 1.3 Annotation Pipeline Architecture

```
Raw Data (images, text, audio)
       ↓
[1] Data Ingestion & Preprocessing
    - Resize images to standard dimensions
    - Normalize audio levels
    - Tokenize text
       ↓
[2] Annotation Queue Management
    - Priority sampling (uncertainty, diversity, difficulty)
    - Load balancing across annotators
    - Task assignment based on expertise
       ↓
[3] Annotation Interface
    - Web-based UI (Label Studio, custom)
    - Desktop app (for specialized tasks)
    - Mobile app (for field collection)
       ↓
[4] Quality Assurance
    - Inter-annotator agreement (Cohen's kappa, Fleiss' kappa)
    - Gold standard validation (known answers)
    - Consensus mechanisms (multiple annotators per item)
       ↓
[5] Annotation Storage
    - Metadata DB (PostgreSQL, DynamoDB)
    - Annotation files (JSON, COCO format, Pascal VOC)
    - Versioning (track annotation changes over time)
       ↓
[6] Export to Training Pipeline
    - Convert to framework-specific format (TFRecord, WebDataset)
    - Split into train/val/test
    - Generate data cards / documentation
```

### 1.4 Annotation Quality Metrics

**Inter-annotator agreement (IAA)**:
```python
from sklearn.metrics import cohen_kappa_score

def compute_iaa(annotations_1, annotations_2):
    """Measure agreement between two annotators"""
    kappa = cohen_kappa_score(annotations_1, annotations_2)
    
    # Interpretation
    if kappa < 0.20:
        return "Slight agreement - need better guidelines"
    elif kappa < 0.40:
        return "Fair agreement - ambiguous categories"
    elif kappa < 0.60:
        return "Moderate agreement - acceptable"
    elif kappa < 0.80:
        return "Substantial agreement - good"
    else:
        return "Almost perfect agreement - excellent"
```

**For object detection**:
```python
def compute_bbox_iou(box1, box2):
    """Intersection over Union for bounding boxes"""
    x1 = max(box1[0], box2[0])
    y1 = max(box1[1], box2[1])
    x2 = min(box1[2], box2[2])
    y2 = min(box1[3], box2[3])
    
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    area1 = (box1[2] - box1[0]) * (box1[3] - box1[1])
    area2 = (box2[2] - box2[0]) * (box2[3] - box2[1])
    union = area1 + area2 - intersection
    
    return intersection / union if union > 0 else 0

# Average IoU across annotators
avg_iou = np.mean([compute_bbox_iou(b1, b2) for b1, b2 in zip(boxes_1, boxes_2)])
```

### 1.5 Active Learning for Annotation

**Purpose**: Minimize annotation cost by selecting the most informative samples

**Strategies**:

**Uncertainty sampling**:
```python
def select_uncertain_samples(model, unlabeled_data, n_samples=100):
    """Select samples where model is most uncertain"""
    predictions = model.predict_proba(unlabeled_data)
    uncertainty = 1 - np.max(predictions, axis=1)  # 1 - max probability
    
    # Select top-n most uncertain
    indices = np.argsort(uncertainty)[-n_samples:]
    return unlabeled_data[indices]
```

**Diversity sampling**:
```python
def select_diverse_samples(embeddings, n_samples=100):
    """Select diverse samples using k-means clustering"""
    from sklearn.cluster import KMeans
    
    kmeans = KMeans(n_clusters=n_samples, random_state=42)
    kmeans.fit(embeddings)
    
    # Select samples closest to cluster centers
    distances = kmeans.transform(embeddings)
    indices = np.argmin(distances, axis=0)
    return indices
```

**Core-set selection**:
```python
def select_coreset(embeddings, n_samples=100):
    """Select representative subset using greedy core-set"""
    from sklearn.metrics import pairwise_distances
    
    selected = []
    remaining = list(range(len(embeddings)))
    
    # Start with random sample
    selected.append(remaining.pop(0))
    
    for _ in range(n_samples - 1):
        # Compute distances to selected points
        dists = pairwise_distances(embeddings[remaining], embeddings[selected])
        min_dists = np.min(dists, axis=1)
        
        # Select point farthest from selected set
        farthest = np.argmax(min_dists)
        selected.append(remaining[farthest])
        remaining.pop(farthest)
    
    return selected
```

**Pipeline integration**:
```python
class ActiveLearningPipeline:
    def __init__(self, model, annotation_queue):
        self.model = model
        self.queue = annotation_queue
    
    def run_iteration(self):
        # 1. Train model on current labeled data
        self.model.fit(labeled_data)
        
        # 2. Select uncertain samples
        uncertain = select_uncertain_samples(self.model, unlabeled_data, n=100)
        
        # 3. Send to annotation queue
        self.queue.add(uncertain, priority="high")
        
        # 4. Wait for annotations
        new_labels = self.queue.wait_for_annotations()
        
        # 5. Add to labeled dataset
        labeled_data.extend(new_labels)
        
        # 6. Repeat
```

### 1.6 Annotation at Scale (Billion-scale)

**Challenges**:
- **Volume**: Billions of images/videos to annotate
- **Velocity**: Continuous data ingestion
- **Variety**: Multiple annotation types (bbox, segmentation, keypoints)
- **Quality**: Maintaining consistency across thousands of annotators

**Solutions**:

**Distributed annotation queue**:
```python
# Kafka-based annotation queue
class DistributedAnnotationQueue:
    def __init__(self, kafka_config):
        self.producer = KafkaProducer(**kafka_config)
        self.consumer = KafkaConsumer(**kafka_config)
    
    def enqueue(self, items: List[AnnotationItem], priority: str = "normal"):
        """Distribute items across partitions"""
        for item in items:
            # Partition by annotator expertise
            partition = hash(item.required_expertise) % self.num_partitions
            self.producer.send(
                topic=f"annotations.{priority}",
                value=item.to_dict(),
                partition=partition
            )
    
    def dequeue(self, annotator_id: str) -> AnnotationItem:
        """Get next item for annotator"""
        # Subscribe to relevant partitions
        return self.consumer.poll(timeout=1000)
```

**Multi-annotator consensus**:
```python
def aggregate_annotations(annotations: List[Annotation]) -> Annotation:
    """Aggregate multiple annotator outputs"""
    if len(annotations) == 1:
        return annotations[0]
    
    # For classification: majority vote
    if annotations[0].type == "classification":
        labels = [a.label for a in annotations]
        return Annotation(label=Counter(labels).most_common(1)[0][0])
    
    # For bounding boxes: average IoU-weighted
    elif annotations[0].type == "bbox":
        boxes = [a.bbox for a in annotations]
        return Annotation(bbox=average_boxes(boxes))
    
    # For segmentation: pixel-wise majority vote
    elif annotations[0].type == "segmentation":
        masks = [a.mask for a in annotations]
        return Annotation(mask=majority_vote_masks(masks))
```

**Annotator performance tracking**:
```python
class AnnotatorPerformance:
    def __init__(self):
        self.metrics = {}
    
    def record_annotation(self, annotator_id, annotation, gold_standard=None):
        """Track annotator accuracy and speed"""
        if gold_standard:
            accuracy = compute_accuracy(annotation, gold_standard)
        else:
            accuracy = None
        
        self.metrics[annotator_id].append({
            "timestamp": now(),
            "accuracy": accuracy,
            "time_spent": annotation.time_spent,
            "complexity": annotation.complexity
        })
    
    def get_performance_report(self, annotator_id):
        """Generate performance report"""
        metrics = self.metrics[annotator_id]
        return {
            "avg_accuracy": np.mean([m["accuracy"] for m in metrics if m["accuracy"]]),
            "avg_time_per_annotation": np.mean([m["time_spent"] for m in metrics]),
            "total_annotations": len(metrics),
            "quality_trend": compute_trend(metrics)
        }
```

---

## 2. Synthetic Data Generation

**Purpose**: Generate artificial training data to augment real datasets, address class imbalance, or create edge cases.

### 2.1 Synthetic Data Use Cases

**Class imbalance**:
```python
# Problem: 99% background, 1% defect
# Solution: Generate synthetic defects

def augment_defect_samples(defect_images, n_synthetic=10000):
    """Generate synthetic defect samples"""
    synthetic_data = []
    
    for _ in range(n_synthetic):
        # Sample random defect
        defect = random.choice(defect_images)
        
        # Place on random background
        background = random.choice(background_images)
        x, y = random_position(background.size, defect.size)
        
        # Composite
        synthetic = composite(background, defect, position=(x, y))
        synthetic_data.append((synthetic, "defect"))
    
    return synthetic_data
```

**Edge cases**:
```python
# Generate rare scenarios
def generate_edge_cases():
    edge_cases = []
    
    # Low lighting
    for img in dataset:
        dark_img = adjust_brightness(img, factor=0.2)
        edge_cases.append((dark_img, img.label))
    
    # Motion blur
    for img in dataset:
        blurred_img = apply_motion_blur(img, angle=45, length=20)
        edge_cases.append((blurred_img, img.label))
    
    # Occlusion
    for img in dataset:
        occluded_img = apply_random_occlusion(img, coverage=0.3)
        edge_cases.append((occluded_img, img.label))
    
    return edge_cases
```

**Domain adaptation**:
```python
# Sim-to-real transfer
def generate_realistic_sim_data(sim_data):
    """Make simulation data look more realistic"""
    domain_adaptor = DomainAdaptationModel()
    
    realistic_data = []
    for sim_img, sim_label in sim_data:
        real_img = domain_adaptor(sim_img)  # Style transfer
        realistic_data.append((real_img, sim_label))
    
    return realistic_data
```

### 2.2 Synthetic Data Generation Techniques

**Traditional augmentation**:
```python
import albumentations as A

transform = A.Compose([
    A.HorizontalFlip(p=0.5),
    A.Rotate(limit=30, p=0.5),
    A.RandomBrightnessContrast(p=0.3),
    A.GaussNoise(p=0.2),
    A.CoarseDropout(max_holes=8, max_height=32, max_width=32, p=0.3),
])

def augment_image(image):
    return transform(image=image)["image"]
```

**GAN-based generation**:
```python
from diffusers import StableDiffusionPipeline

pipe = StableDiffusionPipeline.from_pretrained("stabilityai/stable-diffusion-2")

def generate_synthetic_images(prompt, n_images=100):
    """Generate synthetic images using Stable Diffusion"""
    images = []
    for _ in range(n_images):
        image = pipe(prompt, num_inference_steps=50).images[0]
        images.append(image)
    return images

# Generate synthetic cats
synthetic_cats = generate_synthetic_images("a photo of a cat", n_images=1000)
```

**Diffusion models**:
```python
from diffusers import DiffusionPipeline

def generate_diverse_images(base_prompt, n_variations=100):
    """Generate diverse variations of a concept"""
    pipe = DiffusionPipeline.from_pretrained("stabilityai/stable-diffusion-xl")
    
    variations = []
    for i in range(n_variations):
        # Vary the prompt slightly
        varied_prompt = f"{base_prompt}, style {i % 10}, lighting {i % 5}"
        image = pipe(varied_prompt).images[0]
        variations.append(image)
    
    return variations
```

**3D rendering**:
```python
import bpy  # Blender Python API

def render_3d_models(models, n_views=10):
    """Render 3D models from multiple viewpoints"""
    rendered_images = []
    
    for model in models:
        # Load 3D model
        bpy.ops.import_scene.obj(filepath=model.path)
        
        # Render from multiple angles
        for angle in np.linspace(0, 360, n_views):
            set_camera_position(angle=angle, elevation=30)
            image = render_scene()
            rendered_images.append((image, model.label))
    
    return rendered_images
```

### 2.3 Synthetic Data Quality Validation

**Visual inspection**:
```python
def validate_synthetic_data(synthetic_images, real_images):
    """Compare synthetic vs real distributions"""
    # Compute FID score (Fréchet Inception Distance)
    fid_score = compute_fid(synthetic_images, real_images)
    
    # Lower FID = more similar distributions
    if fid_score < 10:
        return "Excellent quality"
    elif fid_score < 50:
        return "Good quality"
    elif fid_score < 100:
        return "Acceptable quality"
    else:
        return "Poor quality - regenerate"
```

**Model-based validation**:
```python
def validate_with_downstream_model(synthetic_data, test_model):
    """Check if synthetic data improves model performance"""
    # Train on real + synthetic
    model = train_model(real_data + synthetic_data)
    
    # Evaluate on real test set
    accuracy = evaluate(model, real_test_data)
    
    # Compare to baseline (real only)
    baseline_accuracy = evaluate(test_model, real_test_data)
    
    improvement = accuracy - baseline_accuracy
    return improvement > 0  # Synthetic data helped
```

**Diversity metrics**:
```python
def compute_diversity(images):
    """Measure diversity of synthetic dataset"""
    # Compute embeddings
    embeddings = [get_embedding(img) for img in images]
    
    # Compute pairwise distances
    distances = pairwise_distances(embeddings)
    
    # Average distance = diversity
    avg_distance = np.mean(distances[np.triu_indices_from(distances, k=1)])
    
    return avg_distance
```

### 2.4 Synthetic Data Pipeline Architecture

```
Data Requirements
       ↓
[1] Generation Strategy Selection
    - GAN-based (StyleGAN, BigGAN)
    - Diffusion models (Stable Diffusion, DALL-E)
    - 3D rendering (Blender, Unity)
    - Traditional augmentation (Albumentations)
       ↓
[2] Generation Pipeline
    - Batch generation (Spark, Ray)
    - Quality filtering (FID, CLIP score)
    - Deduplication (perceptual hashing)
       ↓
[3] Annotation (if needed)
    - Auto-labeling (use generation parameters)
    - Manual verification (sample-based)
       ↓
[4] Quality Assurance
    - Distribution matching (FID, KS test)
    - Diversity checks (embedding distance)
    - Downstream validation (model improvement)
       ↓
[5] Integration with Training Data
    - Mix with real data (ratio tuning)
    - Version tracking (synthetic vs real)
    - Lineage tracking (which model generated which data)
```

**Orchestration example**:
```python
class SyntheticDataPipeline:
    def __init__(self, generator, validator, storage):
        self.generator = generator
        self.validator = validator
        self.storage = storage
    
    def run(self, requirements: DataRequirements):
        # 1. Generate synthetic data
        synthetic_data = self.generator.generate(
            prompt=requirements.prompt,
            n_samples=requirements.n_samples,
            diversity=requirements.diversity_threshold
        )
        
        # 2. Validate quality
        quality_report = self.validator.validate(
            synthetic_data,
            reference_data=requirements.reference_data
        )
        
        if quality_report.fid_score > requirements.max_fid:
            raise ValueError(f"Quality too low: FID={quality_report.fid_score}")
        
        # 3. Store with metadata
        self.storage.save(
            data=synthetic_data,
            metadata={
                "generator": self.generator.model_name,
                "generation_params": self.generator.params,
                "quality_metrics": quality_report.to_dict(),
                "lineage": f"generated_from_{requirements.prompt}"
            }
        )
        
        return quality_report
```

### 2.5 Lineage Tracking for Synthetic Data

**Purpose**: Track which model generated which data, with what parameters

**Schema**:
```json
{
  "data_id": "synth_12345",
  "source": "synthetic",
  "generator": {
    "model": "stable-diffusion-xl",
    "version": "1.0",
    "checkpoint": "sd-xl-base-1.0.safetensors"
  },
  "generation_params": {
    "prompt": "a photo of a cat",
    "negative_prompt": "blurry, low quality",
    "num_inference_steps": 50,
    "guidance_scale": 7.5,
    "seed": 42
  },
  "quality_metrics": {
    "fid_score": 12.3,
    "clip_score": 0.87,
    "diversity": 0.92
  },
  "created_at": "2024-01-15T10:30:00Z",
  "created_by": "pipeline_v2"
}
```

**Tracking implementation**:
```python
class SyntheticDataLineage:
    def __init__(self, db):
        self.db = db
    
    def log_generation(self, data_id, generator, params, quality_metrics):
        """Log synthetic data generation"""
        self.db.insert("synthetic_data_lineage", {
            "data_id": data_id,
            "generator_model": generator.model_name,
            "generator_version": generator.version,
            "params": json.dumps(params),
            "quality_metrics": json.dumps(quality_metrics),
            "created_at": now()
        })
    
    def get_lineage(self, data_id):
        """Get full lineage for a synthetic data point"""
        return self.db.query(
            "SELECT * FROM synthetic_data_lineage WHERE data_id = ?",
            data_id
        )
    
    def trace_to_model(self, model_id):
        """Find all synthetic data used to train a model"""
        return self.db.query(
            """
            SELECT s.* FROM synthetic_data_lineage s
            JOIN model_training_data m ON s.data_id = m.data_id
            WHERE m.model_id = ?
            """,
            model_id
        )
```

---

## 3. Multimodal Data Handling

**Purpose**: Manage datasets containing multiple modalities (images, video, audio, text) with proper alignment, storage, and processing.

### 3.1 Multimodal Data Types

**Vision**:
- Images (JPEG, PNG, TIFF)
- Video (MP4, AVI, MOV)
- 3D point clouds (PLY, OBJ)
- Depth maps (PNG, NPY)

**Audio**:
- Waveform (WAV, FLAC)
- Spectrograms (PNG, NPY)
- Mel-frequency cepstral coefficients (MFCC)

**Text**:
- Raw text (TXT, JSON)
- Tokenized text (token IDs)
- Embeddings (vectors)

**Structured**:
- Metadata (JSON, CSV)
- Labels (JSON, COCO format)
- Annotations (XML, JSON)

### 3.2 Storage Patterns for Large Binary Assets

**Problem**: Storing billions of images/videos efficiently

**Solution 1: Object storage with metadata DB**:
```python
# Store images in S3, metadata in PostgreSQL
class MultimodalStorage:
    def __init__(self, s3_client, db):
        self.s3 = s3_client
        self.db = db
    
    def store_image(self, image_id, image_bytes, metadata):
        # Store binary in S3
        s3_key = f"images/{image_id}.jpg"
        self.s3.put_object(
            Bucket="ml-data",
            Key=s3_key,
            Body=image_bytes
        )
        
        # Store metadata in DB
        self.db.insert("images", {
            "image_id": image_id,
            "s3_key": s3_key,
            "width": metadata["width"],
            "height": metadata["height"],
            "format": "jpeg",
            "size_bytes": len(image_bytes),
            "created_at": now()
        })
    
    def load_image(self, image_id):
        # Get metadata
        meta = self.db.query("SELECT * FROM images WHERE image_id = ?", image_id)
        
        # Load from S3
        response = self.s3.get_object(Bucket="ml-data", Key=meta["s3_key"])
        image_bytes = response["Body"].read()
        
        return image_bytes, meta
```


**Solution 2: WebDataset (tar-based)**:
```python
import webdataset as wds

# Store images in tar files (efficient for sequential access)
def create_webdataset(image_list, output_path):
    """Create WebDataset from list of images"""
    with wds.ShardWriter(f"{output_path}-%06d.tar", maxcount=10000) as sink:
        for i, (image_id, image_bytes, metadata) in enumerate(image_list):
            sink.write({
                "__key__": f"sample_{i:06d}",
                "jpg": image_bytes,
                "json": metadata
            })

# Load WebDataset efficiently
def load_webdataset(shard_pattern):
    """Load WebDataset with parallel processing"""
    dataset = (
        wds.WebDataset(shard_pattern)
        .decode("rgb")
        .to_tuple("jpg", "json")
        .batched(64)
    )
    return dataset
```

**Solution 3: HDF5/Parquet for structured multimodal**:
```python
import h5py

class MultimodalDataset:
    def __init__(self, path):
        self.h5 = h5py.File(path, "r")
    
    def get_sample(self, idx):
        """Get multimodal sample"""
        return {
            "image": self.h5["images"][idx],
            "audio": self.h5["audio"][idx],
            "text": self.h5["text"][idx].decode(),
            "label": self.h5["labels"][idx]
        }

# Create dataset
with h5py.File("multimodal.h5", "w") as f:
    f.create_dataset("images", data=images_array)
    f.create_dataset("audio", data=audio_array)
    f.create_dataset("text", data=text_array)
    f.create_dataset("labels", data=labels_array)
```

### 3.3 Multimodal Data Alignment

**Problem**: Different modalities have different sampling rates, timestamps, and formats

**Video + Audio alignment**:
```python
import ffmpeg

def align_video_audio(video_path, audio_path, output_path):
    """Align video and audio streams"""
    # Extract video
    video = ffmpeg.input(video_path).video
    
    # Extract and resample audio to match video frame rate
    audio = ffmpeg.input(audio_path).audio.filter("aresample", async=1)
    
    # Mux together
    ffmpeg.output(video, audio, output_path).run()

def extract_aligned_frames(video_path, output_dir, fps=30):
    """Extract frames aligned to audio timestamps"""
    ffmpeg.input(video_path).output(
        f"{output_dir}/frame_%04d.png",
        vf=f"fps={fps}"
    ).run()
```

**Text + Image alignment** (image captioning):
```python
class ImageTextAligner:
    def __init__(self, clip_model):
        self.clip = clip_model
    
    def compute_similarity(self, image, text):
        """Compute CLIP similarity between image and text"""
        image_features = self.clip.encode_image(image)
        text_features = self.clip.encode_text(text)
        
        similarity = torch.cosine_similarity(image_features, text_features)
        return similarity.item()
    
    def filter_aligned_pairs(self, image_text_pairs, threshold=0.25):
        """Filter pairs with low alignment"""
        aligned = []
        for image, text in image_text_pairs:
            sim = self.compute_similarity(image, text)
            if sim >= threshold:
                aligned.append((image, text, sim))
        return aligned
```

**Timestamp-based alignment**:
```python
class MultimodalAligner:
    def align_by_timestamp(self, modalities):
        """Align modalities by timestamp"""
        # Find common time range
        min_time = max(m["start_time"] for m in modalities)
        max_time = min(m["end_time"] for m in modalities)
        
        # Resample each modality to common timeline
        aligned = {}
        for modality in modalities:
            aligned[modality["type"]] = self.resample(
                modality["data"],
                modality["timestamps"],
                start=min_time,
                end=max_time,
                target_fps=30
            )
        
        return aligned
```

### 3.4 Cross-Modal Processing

**Vision-Language models**:
```python
from transformers import CLIPProcessor, CLIPModel

class CrossModalProcessor:
    def __init__(self):
        self.model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14")
        self.processor = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")
    
    def encode_image(self, image):
        """Encode image to embedding"""
        inputs = self.processor(images=image, return_tensors="pt")
        outputs = self.model.get_image_features(**inputs)
        return outputs.squeeze().numpy()
    
    def encode_text(self, text):
        """Encode text to embedding"""
        inputs = self.processor(text=[text], return_tensors="pt")
        outputs = self.model.get_text_features(**inputs)
        return outputs.squeeze().numpy()
    
    def cross_modal_retrieval(self, query_image, text_candidates, top_k=5):
        """Find most relevant text for an image"""
        image_emb = self.encode_image(query_image)
        text_embs = [self.encode_text(t) for t in text_candidates]
        
        similarities = [
            np.dot(image_emb, t_emb) / (np.linalg.norm(image_emb) * np.linalg.norm(t_emb))
            for t_emb in text_embs
        ]
        
        top_indices = np.argsort(similarities)[-top_k:][::-1]
        return [(text_candidates[i], similarities[i]) for i in top_indices]
```

**Audio-Text alignment**:
```python
from transformers import WhisperProcessor, WhisperForConditionalGeneration

class AudioTranscriber:
    def __init__(self):
        self.processor = WhisperProcessor.from_pretrained("openai/whisper-large-v2")
        self.model = WhisperForConditionalGeneration.from_pretrained("openai/whisper-large-v2")
    
    def transcribe_with_timestamps(self, audio_path):
        """Transcribe audio with word-level timestamps"""
        audio, sr = librosa.load(audio_path, sr=16000)
        
        inputs = self.processor(audio, return_tensors="pt", sampling_rate=16000)
        outputs = self.model.generate(
            **inputs,
            return_timestamps="word",
            return_timestamps_word=True
        )
        
        return outputs["words"]  # [{"word": "hello", "timestamp": (0.0, 0.5)}, ...]
```

### 3.5 Multimodal Dataset Management at Scale

**Dataset versioning**:
```python
class MultimodalDatasetVersion:
    def __init__(self, dataset_id, version):
        self.dataset_id = dataset_id
        self.version = version
        self.manifest_path = f"s3://datasets/{dataset_id}/v{version}/manifest.json"
    
    def create_manifest(self, samples):
        """Create dataset manifest"""
        manifest = {
            "dataset_id": self.dataset_id,
            "version": self.version,
            "num_samples": len(samples),
            "modalities": ["image", "text", "audio"],
            "samples": [
                {
                    "id": s["id"],
                    "image_path": s["image_path"],
                    "text": s["text"],
                    "audio_path": s["audio_path"],
                    "labels": s["labels"]
                }
                for s in samples
            ]
        }
        
        # Write manifest to S3
        s3_client.put_object(
            Bucket="datasets",
            Key=f"{self.dataset_id}/v{self.version}/manifest.json",
            Body=json.dumps(manifest)
        )
    
    def load_manifest(self):
        """Load dataset manifest"""
        response = s3_client.get_object(
            Bucket="datasets",
            Key=f"{self.dataset_id}/v{self.version}/manifest.json"
        )
        return json.loads(response["Body"].read())
```

---

## 4. ML Enrichment Pipelines

**Purpose**: Use ML models to enhance, filter, or augment data automatically.

### 4.1 Auto-Labeling with Foundation Models

**Image classification**:
```python
from transformers import AutoImageProcessor, AutoModelForImageClassification

class AutoLabeler:
    def __init__(self, model_name="google/vit-base-patch16-224"):
        self.processor = AutoImageProcessor.from_pretrained(model_name)
        self.model = AutoModelForImageClassification.from_pretrained(model_name)
    
    def label_images(self, images, confidence_threshold=0.8):
        """Auto-label images with foundation model"""
        inputs = self.processor(images=images, return_tensors="pt")
        outputs = self.model(**inputs)
        probs = torch.softmax(outputs.logits, dim=-1)
        
        labels = []
        for i, prob in enumerate(probs):
            max_prob, max_idx = torch.max(prob, dim=0)
            if max_prob >= confidence_threshold:
                label = self.model.config.id2label[max_idx.item()]
                labels.append({"image_id": images[i].id, "label": label, "confidence": max_prob.item()})
        
        return labels
```

**Object detection with grounding**:
```python
from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection

class GroundingDINO:
    def __init__(self):
        self.processor = AutoProcessor.from_pretrained("IDEA-Research/grounding-dino-tiny")
        self.model = AutoModelForZeroShotObjectDetection.from_pretrained("IDEA-Research/grounding-dino-tiny")
    
    def detect_objects(self, image, text_prompt="cat . dog . person ."):
        """Detect objects using text prompts"""
        inputs = self.processor(images=image, text=text_prompt, return_tensors="pt")
        outputs = self.model(**inputs)
        
        results = self.processor.post_process_grounded_object_detection(
            outputs,
            inputs.input_ids,
            box_threshold=0.3,
            text_threshold=0.25,
            target_sizes=[image.size[::-1]]
        )
        
        return results[0]  # {"scores": [...], "labels": [...], "boxes": [...]}
```

### 4.2 Embedding Generation at Scale

**Batch embedding generation**:
```python
class EmbeddingGenerator:
    def __init__(self, model_name="openai/clip-vit-large-patch14"):
        self.model = CLIPModel.from_pretrained(model_name)
        self.processor = CLIPProcessor.from_pretrained(model_name)
    
    def generate_embeddings(self, images, batch_size=32):
        """Generate embeddings for large dataset"""
        embeddings = []
        
        for i in range(0, len(images), batch_size):
            batch = images[i:i+batch_size]
            inputs = self.processor(images=batch, return_tensors="pt")
            
            with torch.no_grad():
                features = self.model.get_image_features(**inputs)
                embeddings.extend(features.cpu().numpy())
        
        return np.array(embeddings)
    
    def generate_and_store(self, images, output_path):
        """Generate embeddings and store in vector DB"""
        embeddings = self.generate_embeddings(images)
        
        # Store in FAISS
        import faiss
        index = faiss.IndexFlatL2(embeddings.shape[1])
        index.add(embeddings)
        faiss.write_index(index, output_path)
```

**Distributed embedding generation**:
```python
from pyspark.sql import SparkSession

def distributed_embedding_generation(image_paths, num_partitions=100):
    """Generate embeddings in parallel using Spark"""
    spark = SparkSession.builder.getOrCreate()
    
    # Distribute images across partitions
    rdd = spark.sparkContext.parallelize(image_paths, num_partitions)
    
    def process_partition(partition):
        # Load model once per partition
        model = EmbeddingGenerator()
        
        embeddings = []
        for path in partition:
            image = load_image(path)
            emb = model.generate_embeddings([image])[0]
            embeddings.append((path, emb.tolist()))
        
        return embeddings
    
    # Process in parallel
    results = rdd.mapPartitions(process_partition).collect()
    
    return results
```

### 4.3 Quality Filtering with ML Models

**Image quality assessment**:
```python
from transformers import AutoImageProcessor, AutoModelForImageClassification

class QualityFilter:
    def __init__(self):
        self.processor = AutoImageProcessor.from_pretrained("google/vit-base-patch16-224")
        self.model = AutoModelForImageClassification.from_pretrained("google/vit-base-patch16-224")
    
    def assess_quality(self, image):
        """Assess image quality (blur, exposure, etc.)"""
        inputs = self.processor(images=image, return_tensors="pt")
        outputs = self.model(**inputs)
        
        # Predict quality score (0-1)
        quality_score = torch.sigmoid(outputs.logits).item()
        return quality_score
    
    def filter_low_quality(self, images, threshold=0.7):
        """Filter out low-quality images"""
        high_quality = []
        
        for image in images:
            score = self.assess_quality(image)
            if score >= threshold:
                high_quality.append(image)
        
        return high_quality
```

**Deduplication with perceptual hashing**:
```python
import imagehash
from PIL import Image

class Deduplicator:
    def __init__(self, hash_size=16):
        self.hash_size = hash_size
    
    def compute_hash(self, image):
        """Compute perceptual hash"""
        return imagehash.phash(Image.open(image), hash_size=self.hash_size)
    
    def find_duplicates(self, images, threshold=5):
        """Find duplicate images based on perceptual hash"""
        hashes = {}
        duplicates = []
        
        for image_path in images:
            img_hash = self.compute_hash(image_path)
            
            # Check for similar hashes
            for existing_path, existing_hash in hashes.items():
                if abs(img_hash - existing_hash) <= threshold:
                    duplicates.append((image_path, existing_path))
                    break
            
            hashes[image_path] = img_hash
        
        return duplicates
```

### 4.4 ML Enrichment Pipeline Architecture

```
Raw Data
   ↓
[1] Quality Assessment
    - Image quality (blur, exposure)
    - Audio quality (noise, clipping)
    - Text quality (length, language)
   ↓
[2] Deduplication
    - Perceptual hashing (images)
    - Text similarity (embeddings)
    - Audio fingerprinting
   ↓
[3] Auto-Labeling
    - Foundation models (CLIP, GPT-4)
    - Object detection (Grounding DINO)
    - Segmentation (SAM)
   ↓
[4] Embedding Generation
    - Image embeddings (CLIP, DINO)
    - Text embeddings (BERT, GPT)
    - Audio embeddings (Whisper, Wav2Vec)
   ↓
[5] Enrichment Storage
    - Quality scores
    - Labels + confidence
    - Embeddings (vector DB)
    - Metadata
   ↓
[6] Integration with Training Pipeline
    - Filter by quality
    - Sample by diversity
    - Balance by label
```

---

## 5. Agentic Capabilities in Pipelines

**Purpose**: Use LLMs and AI agents to automate data operations, validation, and decision-making.

### 5.1 LLM-Based Data Validation

**Schema validation with LLMs**:
```python
from openai import OpenAI

class LLMDataValidator:
    def __init__(self):
        self.client = OpenAI()
    
    def validate_annotation(self, annotation, schema):
        """Use LLM to validate annotation against schema"""
        prompt = f"""
        Validate this annotation against the schema:
        
        Schema: {json.dumps(schema)}
        Annotation: {json.dumps(annotation)}
        
        Return JSON with:
        - valid: boolean
        - errors: list of error messages
        - suggestions: list of improvement suggestions
        """
        
        response = self.client.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"}
        )
        
        return json.loads(response.choices[0].message.content)
```

**Automated data quality checks**:
```python
class AutomatedQualityChecker:
    def __init__(self):
        self.llm = OpenAI()
    
    def check_data_quality(self, dataset_sample):
        """Use LLM to identify data quality issues"""
        prompt = f"""
        Analyze this dataset sample and identify quality issues:
        
        Sample: {json.dumps(dataset_sample[:100])}
        
        Check for:
        - Missing values
        - Inconsistent formats
        - Outliers
        - Label errors
        - Duplicates
        
        Return JSON with issues found and severity (high/medium/low).
        """
        
        response = self.llm.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"}
        )
        
        return json.loads(response.choices[0].message.content)
```

### 5.2 Intelligent Data Routing

**Priority-based routing**:
```python
class IntelligentRouter:
    def __init__(self):
        self.llm = OpenAI()
    
    def route_annotation_task(self, task):
        """Route task to appropriate annotator based on complexity"""
        prompt = f"""
        Analyze this annotation task and determine:
        - Complexity (simple/medium/complex)
        - Required expertise (general/domain-specific)
        - Estimated time (seconds)
        
        Task: {json.dumps(task)}
        
        Return JSON with routing decision.
        """
        
        response = self.llm.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"}
        )
        
        routing = json.loads(response.choices[0].message.content)
        
        if routing["complexity"] == "simple":
            return "junior_annotator_queue"
        elif routing["complexity"] == "medium":
            return "senior_annotator_queue"
        else:
            return "expert_annotator_queue"
```

**Dynamic load balancing**:
```python
class DynamicLoadBalancer:
    def __init__(self, annotator_pool):
        self.annotators = annotator_pool
        self.llm = OpenAI()
    
    def balance_workload(self, pending_tasks):
        """Dynamically balance workload across annotators"""
        # Get current workload
        workloads = {a.id: a.get_pending_count() for a in self.annotators}
        
        # Use LLM to optimize assignment
        prompt = f"""
        Optimize task assignment to annotators:
        
        Pending tasks: {len(pending_tasks)}
        Annotator workloads: {json.dumps(workloads)}
        
        Assign tasks to minimize completion time while respecting:
        - Annotator expertise
        - Task complexity
        - Fair workload distribution
        
        Return JSON mapping task_id -> annotator_id.
        """
        
        response = self.llm.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"}
        )
        
        return json.loads(response.choices[0].message.content)
```

### 5.3 Self-Healing Pipelines

**Automatic error recovery**:
```python
class SelfHealingPipeline:
    def __init__(self):
        self.llm = OpenAI()
    
    def diagnose_failure(self, error_log, pipeline_config):
        """Use LLM to diagnose pipeline failure"""
        prompt = f"""
        Diagnose this pipeline failure and suggest fixes:
        
        Error log: {error_log}
        Pipeline config: {json.dumps(pipeline_config)}
        
        Identify:
        - Root cause
        - Immediate fix
        - Long-term prevention
        
        Return JSON with diagnosis and fix steps.
        """
        
        response = self.llm.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"}
        )
        
        diagnosis = json.loads(response.choices[0].message.content)
        
        # Apply automatic fix if possible
        if diagnosis["can_auto_fix"]:
            self.apply_fix(diagnosis["fix_steps"])
        
        return diagnosis
    
    def apply_fix(self, fix_steps):
        """Apply automatic fix"""
        for step in fix_steps:
            if step["type"] == "restart_component":
                self.restart(step["component"])
            elif step["type"] == "adjust_config":
                self.update_config(step["config_path"], step["new_value"])
            elif step["type"] == "retry_task":
                self.retry(step["task_id"])
```

### 5.4 Agentic Pipeline Architecture

```
Pipeline Execution
       ↓
[1] Monitoring Agent
    - Track metrics (throughput, latency, errors)
    - Detect anomalies
    - Log events
       ↓
[2] Diagnosis Agent
    - Analyze errors with LLM
    - Identify root cause
    - Suggest fixes
       ↓
[3] Decision Agent
    - Evaluate fix options
    - Assess risk
    - Decide: auto-fix vs. human intervention
       ↓
[4] Action Agent
    - Apply automatic fixes
    - Restart components
    - Adjust configurations
       ↓
[5] Validation Agent
    - Verify fix worked
    - Check pipeline health
    - Update knowledge base
```

---

## 6. Self-Service Tools for Data Teams

**Purpose**: Enable non-engineers (data scientists, annotators, PMs) to explore, query, and manage data without writing code.

### 6.1 Data Exploration Tools

**Interactive dataset browser**:
```python
import streamlit as st
import pandas as pd

def dataset_browser():
    """Streamlit app for exploring datasets"""
    st.title("Dataset Explorer")
    
    # Load dataset manifest
    dataset_id = st.selectbox("Select dataset", list_datasets())
    manifest = load_manifest(dataset_id)
    
    # Filter options
    st.sidebar.header("Filters")
    label_filter = st.sidebar.multiselect("Labels", manifest["labels"])
    quality_threshold = st.sidebar.slider("Min quality", 0.0, 1.0, 0.5)
    
    # Display samples
    samples = filter_samples(manifest, label_filter, quality_threshold)
    
    for sample in samples[:100]:
        col1, col2 = st.columns(2)
        with col1:
            st.image(load_image(sample["image_path"]))
        with col2:
            st.write(f"**Label**: {sample['label']}")
            st.write(f"**Quality**: {sample['quality_score']:.2f}")
            st.write(f"**Metadata**: {sample['metadata']}")
```

**Query builder for non-engineers**:
```python
class QueryBuilder:
    def __init__(self):
        self.filters = []
    
    def add_filter(self, field, operator, value):
        """Add filter to query"""
        self.filters.append({
            "field": field,
            "operator": operator,
            "value": value
        })
    
    def build_sql(self):
        """Build SQL query from filters"""
        where_clauses = []
        for f in self.filters:
            if f["operator"] == "equals":
                where_clauses.append(f"{f['field']} = '{f['value']}'")
            elif f["operator"] == "greater_than":
                where_clauses.append(f"{f['field']} > {f['value']}")
            # ... more operators
        
        sql = f"SELECT * FROM dataset WHERE {' AND '.join(where_clauses)}"
        return sql
    
    def execute(self):
        """Execute query and return results"""
        sql = self.build_sql()
        return spark.sql(sql)
```

### 6.2 Dataset Versioning and Discovery

**Dataset catalog**:
```python
class DatasetCatalog:
    def __init__(self, db):
        self.db = db
    
    def register_dataset(self, dataset_info):
        """Register new dataset in catalog"""
        self.db.insert("dataset_catalog", {
            "dataset_id": dataset_info["id"],
            "name": dataset_info["name"],
            "description": dataset_info["description"],
            "owner": dataset_info["owner"],
            "modalities": dataset_info["modalities"],
            "num_samples": dataset_info["num_samples"],
            "size_gb": dataset_info["size_gb"],
            "tags": dataset_info["tags"],
            "created_at": now(),
            "updated_at": now()
        })
    
    def search_datasets(self, query):
        """Search datasets by name, description, tags"""
        results = self.db.query(
            """
            SELECT * FROM dataset_catalog
            WHERE name LIKE ? OR description LIKE ? OR tags LIKE ?
            """,
            f"%{query}%", f"%{query}%", f"%{query}%"
        )
        return results
```


**Version tracking**:
```python
class DatasetVersioning:
    def __init__(self, dataset_id):
        self.dataset_id = dataset_id
    
    def create_version(self, changes, description):
        """Create new dataset version"""
        version_id = self.get_next_version()
        
        self.db.insert("dataset_versions", {
            "dataset_id": self.dataset_id,
            "version": version_id,
            "description": description,
            "changes": json.dumps(changes),
            "created_at": now(),
            "parent_version": self.get_current_version()
        })
        
        return version_id
    
    def diff_versions(self, v1, v2):
        """Compare two dataset versions"""
        manifest1 = self.load_manifest(v1)
        manifest2 = self.load_manifest(v2)
        
        diff = {
            "added": set(manifest2["sample_ids"]) - set(manifest1["sample_ids"]),
            "removed": set(manifest1["sample_ids"]) - set(manifest2["sample_ids"]),
            "modified": []
        }
        
        # Find modified samples
        common = set(manifest1["sample_ids"]) & set(manifest2["sample_ids"])
        for sample_id in common:
            s1 = manifest1["samples"][sample_id]
            s2 = manifest2["samples"][sample_id]
            if s1 != s2:
                diff["modified"].append(sample_id)
        
        return diff
```

### 6.3 Data Catalog with Search

**Full-text search**:
```python
from elasticsearch import Elasticsearch

class DataCatalogSearch:
    def __init__(self):
        self.es = Elasticsearch()
        self.index = "dataset_catalog"
    
    def index_dataset(self, dataset):
        """Index dataset for search"""
        self.es.index(
            index=self.index,
            id=dataset["id"],
            body={
                "name": dataset["name"],
                "description": dataset["description"],
                "tags": dataset["tags"],
                "modalities": dataset["modalities"],
                "num_samples": dataset["num_samples"],
                "owner": dataset["owner"],
                "created_at": dataset["created_at"]
            }
        )
    
    def search(self, query, filters=None):
        """Search datasets with filters"""
        body = {
            "query": {
                "bool": {
                    "must": [
                        {"multi_match": {
                            "query": query,
                            "fields": ["name^3", "description", "tags^2"]
                        }}
                    ],
                    "filter": []
                }
            }
        }
        
        if filters:
            if "modalities" in filters:
                body["query"]["bool"]["filter"].append(
                    {"terms": {"modalities": filters["modalities"]}}
                )
            if "min_samples" in filters:
                body["query"]["bool"]["filter"].append(
                    {"range": {"num_samples": {"gte": filters["min_samples"]}}}
                )
        
        results = self.es.search(index=self.index, body=body)
        return [hit["_source"] for hit in results["hits"]["hits"]]
```

---

## 7. Petabyte-Scale Data Patterns

**Purpose**: Handle datasets that exceed single-machine memory and require distributed processing.

### 7.1 Data Partitioning Strategies

**Time-based partitioning**:
```python
# Partition by date for time-series data
def partition_by_time(df, time_col="timestamp"):
    """Partition DataFrame by time"""
    return df.withColumn("partition_date", F.to_date(F.col(time_col))) \
             .repartition("partition_date")

# Write partitioned
df.write \
  .partitionBy("partition_date") \
  .parquet("s3://data/features/")

# Read specific partition (efficient)
df = spark.read.parquet("s3://data/features/partition_date=2024-01-15/")
```

**Hash-based partitioning**:
```python
# Partition by entity ID for consistent access patterns
def partition_by_entity(df, entity_col="user_id", num_partitions=1000):
    """Partition by hash of entity ID"""
    return df.withColumn(
        "partition_id",
        F.abs(F.hash(F.col(entity_col))) % num_partitions
    ).repartition("partition_id")

# Write partitioned
df.write \
  .partitionBy("partition_id") \
  .parquet("s3://data/users/")

# Read specific partition (all data for one user)
df = spark.read.parquet("s3://data/users/partition_id=42/")
```

**Range-based partitioning**:
```python
# Partition by value ranges (e.g., confidence scores)
def partition_by_range(df, col, ranges):
    """Partition by value ranges"""
    conditions = []
    for i, (low, high) in enumerate(ranges):
        conditions.append(
            F.when((F.col(col) >= low) & (F.col(col) < high), i)
        )
    
    return df.withColumn("partition_id", conditions[0]) \
             .repartition("partition_id")

# Example: partition by confidence
ranges = [(0.0, 0.5), (0.5, 0.7), (0.7, 0.9), (0.9, 1.0)]
df = partition_by_range(df, "confidence", ranges)
```

### 7.2 Incremental Processing Patterns

**Change Data Capture (CDC)**:
```python
class CDCProcessor:
    def __init__(self, checkpoint_path):
        self.checkpoint_path = checkpoint_path
    
    def process_incremental(self, source_path, target_path):
        """Process only new/changed data"""
        # Read checkpoint
        last_timestamp = self.load_checkpoint()
        
        # Read new data
        new_data = spark.read.parquet(source_path) \
            .filter(F.col("updated_at") > last_timestamp)
        
        if new_data.count() == 0:
            return
        
        # Process
        processed = self.transform(new_data)
        
        # Merge with existing (upsert)
        processed.write \
            .mode("overwrite") \
            .partitionBy("date") \
            .parquet(target_path)
        
        # Update checkpoint
        self.save_checkpoint(new_data.agg(F.max("updated_at")).first()[0])
```

**Streaming with micro-batches**:
```python
# Spark Structured Streaming
query = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "localhost:9092") \
    .option("subscribe", "raw_data") \
    .load() \
    .select(F.from_json(F.col("value").cast("string"), schema).alias("data")) \
    .select("data.*")

# Process each micro-batch
def process_batch(batch_df, batch_id):
    # Transform
    features = compute_features(batch_df)
    
    # Write to online store
    for row in features.collect():
        redis.hset(f"features:{row.entity_id}", mapping=row.asDict())

query.writeStream \
    .foreachBatch(process_batch) \
    .option("checkpointLocation", "/checkpoints/stream") \
    .start()
```

### 7.3 Cost Optimization at Scale

**Tiered storage**:
```python
class TieredStorageManager:
    def __init__(self):
        self.s3 = boto3.client("s3")
    
    def move_to_cold_storage(self, dataset_path, age_days=90):
        """Move old data to cheaper storage"""
        cutoff_date = datetime.now() - timedelta(days=age_days)
        
        # List objects
        paginator = self.s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket="ml-data", Prefix=dataset_path):
            for obj in page.get("Contents", []):
                if obj["LastModified"] < cutoff_date:
                    # Transition to Glacier
                    self.s3.restore_object(
                        Bucket="ml-data",
                        Key=obj["Key"],
                        RestoreRequest={"Days": 1}
                    )
                    # Or use lifecycle policies (better)
    
    def setup_lifecycle_policy(self, bucket, prefix):
        """Set up automatic tiering"""
        self.s3.put_bucket_lifecycle_configuration(
            Bucket=bucket,
            LifecycleConfiguration={
                "Rules": [
                    {
                        "ID": "MoveToIAAfter30Days",
                        "Prefix": prefix,
                        "Status": "Enabled",
                        "Transitions": [
                            {"Days": 30, "StorageClass": "STANDARD_IA"},
                            {"Days": 90, "StorageClass": "GLACIER"},
                            {"Days": 365, "StorageClass": "DEEP_ARCHIVE"}
                        ]
                    }
                ]
            }
        )
```

**Compression strategies**:
```python
# Use Parquet with Snappy compression (good balance)
df.write \
  .option("compression", "snappy") \
  .parquet("s3://data/features/")

# For images: use WebP instead of PNG
def compress_image(image_path):
    img = Image.open(image_path)
    img.save(image_path.replace(".png", ".webp"), "WEBP", quality=85)

# For embeddings: use float16 instead of float32
embeddings_f16 = embeddings.astype(np.float16)
# Saves 50% storage, minimal accuracy loss
```

**Spot instances for batch jobs**:
```python
# Use spot instances for fault-tolerant batch jobs
spark_conf = {
    "spark.executor.instances": "100",
    "spark.hadoop.fs.s3a.connection.maximum": "1000",
    "spark.kubernetes.executor.request.cores": "4",
    "spark.kubernetes.executor.limit.cores": "8",
    # Use spot instances
    "spark.kubernetes.node.selector.node.kubernetes.io/capacityType": "spot"
}

spark = SparkSession.builder \
    .config(conf=spark_conf) \
    .getOrCreate()
```

### 7.4 Multi-Region Data Replication

**Cross-region replication**:
```python
class MultiRegionReplicator:
    def __init__(self, regions):
        self.regions = regions  # ["us-east-1", "eu-west-1", "ap-southeast-1"]
    
    def replicate_dataset(self, dataset_path):
        """Replicate dataset to all regions"""
        for region in self.regions:
            # Copy to region-specific bucket
            target_bucket = f"ml-data-{region}"
            
            # Use S3 batch operations for large datasets
            self.s3.copy_object(
                CopySource={"Bucket": "ml-data-us-east-1", "Key": dataset_path},
                Bucket=target_bucket,
                Key=dataset_path
            )
    
    def read_from_nearest_region(self, dataset_path):
        """Read from nearest region"""
        # Determine nearest region based on latency
        nearest = self.get_nearest_region()
        bucket = f"ml-data-{nearest}"
        
        return spark.read.parquet(f"s3://{bucket}/{dataset_path}")
```

---

## 8. Data Quality & Governance

**Purpose**: Ensure data is correct, complete, consistent, and compliant.

### 8.1 Data Quality Framework

**Automated quality checks**:
```python
from great_expectations.core import ExpectationSuite

class DataQualityFramework:
    def __init__(self):
        self.suites = {}
    
    def create_suite(self, dataset_name):
        """Create quality suite for dataset"""
        suite = ExpectationSuite(f"{dataset_name}_quality")
        
        # Schema validation
        suite.add_expectation(
            ExpectTableColumnsToMatchOrderless(
                column_list=["image_id", "label", "confidence", "timestamp"]
            )
        )
        
        # Value ranges
        suite.add_expectation(
            ExpectColumnValuesToBeBetween("confidence", min_value=0, max_value=1)
        )
        
        # Null checks
        suite.add_expectation(
            ExpectColumnValuesToNotBeNull("image_id", mostly=1.0)
        )
        
        # Uniqueness
        suite.add_expectation(
            ExpectColumnValuesToBeUnique("image_id")
        )
        
        self.suites[dataset_name] = suite
        return suite
    
    def validate(self, dataset_name, df):
        """Run quality checks"""
        suite = self.suites[dataset_name]
        results = suite.validate(df)
        
        if not results["success"]:
            # Send alerts
            for failure in results["results"]:
                if not failure["success"]:
                    send_alert(f"Quality check failed: {failure['expectation_config']}")
        
        return results
```

### 8.2 Data Lineage Tracking

**End-to-end lineage**:
```python
class DataLineageTracker:
    def __init__(self, db):
        self.db = db
    
    def log_ingestion(self, source, destination, metadata):
        """Log data ingestion"""
        self.db.insert("data_lineage", {
            "source": source,
            "destination": destination,
            "operation": "ingestion",
            "metadata": json.dumps(metadata),
            "timestamp": now()
        })
    
    def log_transformation(self, input_datasets, output_dataset, transformation):
        """Log data transformation"""
        self.db.insert("data_lineage", {
            "source": json.dumps(input_datasets),
            "destination": output_dataset,
            "operation": "transformation",
            "transformation": transformation,
            "timestamp": now()
        })
    
    def trace_lineage(self, dataset_id):
        """Trace full lineage of a dataset"""
        lineage = []
        current = dataset_id
        
        while current:
            record = self.db.query(
                "SELECT * FROM data_lineage WHERE destination = ?",
                current
            )
            if record:
                lineage.append(record)
                current = record["source"]
            else:
                break
        
        return lineage
    
    def impact_analysis(self, dataset_id):
        """Find all downstream datasets affected by changes"""
        impacted = []
        queue = [dataset_id]
        
        while queue:
            current = queue.pop(0)
            downstream = self.db.query(
                "SELECT destination FROM data_lineage WHERE source LIKE ?",
                f"%{current}%"
            )
            for ds in downstream:
                impacted.append(ds)
                queue.append(ds)
        
        return impacted
```

### 8.3 Compliance & Privacy

**PII detection and masking**:
```python
import re

class PIIDetector:
    def __init__(self):
        self.patterns = {
            "email": r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+",
            "phone": r"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b",
            "ssn": r"\b\d{3}-\d{2}-\d{4}\b",
            "credit_card": r"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"
        }
    
    def detect_pii(self, text):
        """Detect PII in text"""
        found = {}
        for pii_type, pattern in self.patterns.items():
            matches = re.findall(pattern, text)
            if matches:
                found[pii_type] = matches
        return found
    
    def mask_pii(self, text):
        """Mask PII in text"""
        masked = text
        for pii_type, pattern in self.patterns.items():
            masked = re.sub(pattern, f"[{pii_type.upper()}]", masked)
        return masked

# Apply to dataset
def mask_pii_in_dataset(df, text_columns):
    detector = PIIDetector()
    
    for col in text_columns:
        df = df.withColumn(
            f"{col}_masked",
            F.udf(lambda x: detector.mask_pii(x) if x else None)(F.col(col))
        )
    
    return df
```

**GDPR compliance**:
```python
class GDPRCompliance:
    def __init__(self, db):
        self.db = db
    
    def handle_deletion_request(self, user_id):
        """Handle right to deletion"""
        # Find all data for user
        datasets = self.find_user_data(user_id)
        
        # Delete from all datasets
        for dataset in datasets:
            self.delete_from_dataset(dataset, user_id)
        
        # Log deletion
        self.db.insert("gdpr_deletions", {
            "user_id": user_id,
            "datasets_affected": json.dumps(datasets),
            "timestamp": now()
        })
    
    def export_user_data(self, user_id):
        """Handle data portability request"""
        data = {}
        datasets = self.find_user_data(user_id)
        
        for dataset in datasets:
            data[dataset] = self.extract_user_data(dataset, user_id)
        
        # Export in standard format (JSON)
        return json.dumps(data, indent=2)
```

---

## 9. Real-World Case Studies

### Case Study 1: Apple Vision Pro Training Data Pipeline

**Challenge**: Build training dataset for hand tracking model with 1B+ images

**Architecture**:
```
Raw video captures (100K hours)
       ↓
[1] Frame extraction (Spark, 1000 cores)
    - Extract 30 fps → 10B frames
    - Deduplicate (perceptual hashing)
    - Filter low-quality (blur, occlusion)
       ↓
[2] Annotation pipeline
    - 500 annotators (Scale AI)
    - 2D keypoints (21 points per hand)
    - 3D pose estimation
    - Quality assurance (3x annotation, consensus)
       ↓
[3] Synthetic augmentation
    - Generate edge cases (occlusion, unusual poses)
    - 3D rendering (Blender, 10M synthetic samples)
    - Domain adaptation (sim-to-real transfer)
       ↓
[4] Training data assembly
    - Point-in-time join (video metadata + annotations)
    - Train/val/test split (temporal, not random)
    - Balance by hand pose, lighting, occlusion
       ↓
[5] Model training
    - Distributed training (1000 GPUs)
    - Mixed precision (FP16)
    - Gradient accumulation
       ↓
[6] Evaluation & deployment
    - Latency profiling (<10ms inference)
    - Accuracy on edge cases
    - A/B testing in production
```

**Scale**: 10B frames, 500M annotated, 100M training samples

**Latency**: 2 weeks from raw video to trained model

**Cost**: $500K (annotation) + $200K (compute) = $700K total

### Case Study 2: Siri Speech Recognition Data Pipeline

**Challenge**: Continuous improvement of speech recognition with billions of audio samples

**Architecture**:
```
User audio (anonymized, opt-in)
       ↓
[1] Ingestion pipeline (Kafka, Flink)
    - Stream 1M audio samples/hour
    - Real-time quality filtering (SNR, duration)
    - Deduplication (audio fingerprinting)
       ↓
[2] Transcription pipeline
    - Auto-transcribe with existing model (Whisper)
    - Human review (sample 10% for quality)
    - Active learning (select uncertain samples)
       ↓
[3] Enrichment pipeline
    - Speaker diarization (who is speaking)
    - Language identification
    - Accent classification
    - Emotion detection
       ↓
[4] Storage (Iceberg on S3)
    - Partition by date, language, accent
    - Columnar format (Parquet)
    - Metadata catalog (Hive metastore)
       ↓
[5] Training data assembly
    - Sample by diversity (accent, language, noise)
    - Balance by use case (commands, dictation, queries)
    - Temporal split (train on old, test on new)
       ↓
[6] Continuous training
    - Daily incremental training
    - Weekly full retraining
    - A/B testing in production
       ↓
[7] Monitoring
    - Drift detection (hourly)
    - Accuracy by accent/language
    - Latency profiling
```

**Scale**: 10B audio samples, 50 languages, 100 accents

**Latency**: 1 hour from audio capture to model update

**Cost**: $2M/month (storage + compute + annotation)

---

## 10. Key Takeaways for Your Interview

### Technical Depth

**Data annotation**:
- Understand active learning (uncertainty, diversity, core-set sampling)
- Know inter-annotator agreement metrics (Cohen's kappa, IoU)
- Be familiar with annotation tools (Label Studio, CVAT, Scale AI)

**Synthetic data**:
- Know generation techniques (GANs, diffusion models, 3D rendering)
- Understand quality validation (FID, CLIP score, diversity metrics)
- Be able to discuss lineage tracking (which model generated which data)

**Multimodal data**:
- Understand alignment challenges (video+audio, image+text)
- Know storage patterns (object storage + metadata DB, WebDataset, HDF5)
- Be familiar with cross-modal models (CLIP, Whisper)

**Petabyte-scale**:
- Understand partitioning strategies (time, hash, range)
- Know incremental processing (CDC, streaming)
- Be able to discuss cost optimization (tiered storage, compression, spot instances)

### System Design

**Be ready to design**:
1. **Annotation pipeline**: How to annotate 1B images efficiently
2. **Synthetic data pipeline**: How to generate and validate synthetic data
3. **Multimodal dataset**: How to store and query image+text+audio data
4. **Drift detection**: How to detect and respond to data drift in production

**Key tradeoffs**:
- Batch vs. streaming (latency vs. complexity)
- Manual vs. automated annotation (quality vs. cost)
- Real vs. synthetic data (diversity vs. distribution shift)
- Centralized vs. decentralized data ownership (consistency vs. autonomy)

### Behavioral Questions

**Be ready to discuss**:
- A time you scaled a data pipeline to handle 10x more data
- A time you improved data quality and measured the impact
- A time you mentored junior engineers on data engineering best practices
- A time you influenced a partner team's roadmap to build a feature you needed

**Show impact**:
- Quantify everything (10B samples, 50% cost reduction, 2x faster pipeline)
- Focus on business outcomes (model accuracy improved 5%, latency reduced 30%)
- Highlight leadership (led team of 5, influenced 3 partner teams)

---

## 11. Questions to Ask Them

**Technical**:
- What's the current scale of your data pipelines (samples/day, storage size)?
- What annotation tools do you use (in-house or third-party)?
- How do you handle synthetic data generation and validation?
- What's your approach to data quality monitoring and drift detection?

**Process**:
- How do you prioritize data infrastructure work vs. feature development?
- How do you collaborate with R&D teams on data requirements?
- What's your approach to mentoring and growing engineers?

**Challenges**:
- What are the biggest data challenges you're facing right now?
- What does success look like for this role in the first 6 months?
- How do you balance short-term deliveries with long-term infrastructure improvements?

---

**Final advice**: This role is about **data operations at scale**, not just ML infrastructure. Focus on:
1. Annotation workflows (manual, semi-automated, active learning)
2. Synthetic data generation (GANs, diffusion models, quality validation)
3. Multimodal data handling (vision, audio, text, alignment)
4. Petabyte-scale patterns (partitioning, incremental processing, cost optimization)
5. Data quality & governance (lineage, compliance, monitoring)

You've got this! 🚀
