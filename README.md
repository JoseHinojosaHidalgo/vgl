# Visual Geolocalization from aerial images on NVIDIA Jetson Orin Nano
This repository allows to run on a PC or on the Orin Visual Geolocalization.


## Table of Contents

- [Visual Geolocalization from aerial images on NVIDIA Jetson Orin Nano](#visual-geolocalization-from-aerial-images-on-nvidia-jetson-orin-nano)
	- [Table of Contents](#table-of-contents)
	- [Overview](#overview)
	- [Usage](#usage)
	- [ODM](#odm)
	- [Visual Localization](#visual-localization)
- [Acknowledgments](#acknowledgments)
- [References](#references)
- [License](#license)

## Overview

The following figure shows the architecture of the visual localization system. The system is composed of three main components: Key Point Detection and Description, Key Point Matching and Localization. The Key Point Detection and Description component detects and describes key points in both the query image and the satellite images. The Key Point Matching component matches the key points between the query image and the satellite images. The Localization component estimates the pose of the UAV in the satellite geo-referenced database.

![Architecture](assets/project_overview.png)

Here are some examples of localization algorithm:

![sample 01](assets/sample_01.jpg)

In this example, the query image has a sparse set of key points that are matched with the satellite image.
 ![sample 02](assets/sample_02.jpg)


## Usage

You need to use gitmodules to clone the *superglue_lib* submodule:

```bash
git submodule update --init --recursive
```

To install the dependencies, you need to use *poetry*. If you don't have it installed, you can install it using the following command:

```bash
pip install poetry
```

Then you can install the dependencies using the following command:

```bash
poetry install
```
This will install all the dependencies needed for the project (including the dev, docs and tests dependencies). If you want to install only the dependencies needed for the project, you can use the following command:

```bash
poetry install --only main
```

In newer versions of poetry you might need to install the *shell plugin*

```bash
poetry self add poetry-plugin-shell 
```

To activate the virtual environment, you can use the following command:

```bash
poetry shell
```

To run the main script, you can use the following command:

```bash
poetry run python scripts/main.py
```

## ODM

## Visual Localization

Before you run your code, you need to have:

1. A satellite geo-referenced database that contains the satellite images, stored in the **data/maps** directory. Feel free to use the provided database or create your own database.
2. A query image dataset that contains the query images, stored in the **data/query** directory. Feel free to use the provided dataset or create your own dataset.
3. Make sure that the metadata file of the satellite images and the query images are stored in the **data/maps** and **data/query** directories respectively.

To localize the UAV in the satellite geo-referenced database, you can use the **svl.localization.Pipeline** class to run the full pipeline.

```python
from svl.localization.pipeline import Pipeline

# create the map reader
map_reader = SatelliteMapReader(...)

# create the drone streamer
streamer = DroneStreamer(...)

# create the detector
superpoint_algorithm = SuperPointAlgorithm(...)

# create the matcher
superglue_matcher = SuperGlueMatcher(...)

# create the query processor
query_processor = QueryProcessor(...)

# create the config
config = Config(...)

# create the logger
logger = Logger(...)

# create the pipeline
pipeline = Pipeline(
    map_reader=map_reader,
    drone_streamer=streamer,
    detector=superpoint_algorithm,
    matcher=superglue_matcher,
    query_processor=query_processor,
    config=config,
    logger=logger,
)

# run the pipeline
preds = pipeline.run(output_path="path/to/output/directory")
metrics = pipeline.compute_metrics(preds)
```

For a complete example, you can check the **scripts/main.py** script. The script runs the full pipeline on the provided geo-referenced database and query images and saves the results in the **data/output** directory.


# Acknowledgments

The original implementation of the paper can be found [here](https://github.com/TIERS/wildnav). I would like to thank the authors of the paper for making their code available.

I would also like to thank the authors of the SuperPoint/SuperGlue for making their code available. The code as well as the weights can be found [here](https://github.com/magicleap/SuperGluePretrainedNetwork).

Finally, I hope this project will be useful for other researchers and developers who are working on visual localization for UAVs using satellite imagery.

# References

* [Vision-based GNSS-Free Localization for UAVs in the Wild](https://arxiv.org/abs/2210.09727)
* [SuperPoint: Self-Supervised Interest Point Detection and Description](https://arxiv.org/abs/1712.07629)
* [SuperGlue: Learning Feature Matching with Graph Neural Networks](https://arxiv.org/abs/1911.11763)


# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
