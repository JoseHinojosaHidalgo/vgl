# Visual Geolocalization from aerial images on NVIDIA Jetson Orin Nano
This repository allows to run on a PC or on the Orin the Visual Geolocalization.


## Table of Contents

- [Visual Geolocalization from aerial images on NVIDIA Jetson Orin Nano](#visual-geolocalization-from-aerial-images-on-nvidia-jetson-orin-nano)
	- [Table of Contents](#table-of-contents)
	- [Overview](#overview)
	- [Requirements](#requirements)
	- [Usage](#usage)
	- [ODM](#odm)
	- [Visual Localization](#visual-localization)
- [Acknowledgments](#acknowledgments)
- [References](#references)
- [License](#license)

## Overview

This project integrates Open Drone Map and visual geolocalization to enable GPS free localization with images from any altitude. 

ODM is used to compose and orthorectify low altitude iamges into bigger images that can be matched to satellite data, this matching is done using deep learning algorithms like Superpoint and Superglue.

The following figure shows the architecture of the visual localization system. The system is composed of three main components: Key Point Detection and Description, Key Point Matching and Localization. The Key Point Detection and Description component detects and describes key points in both the query image and the satellite images. The Key Point Matching component matches the key points between the query image and the satellite images. The Localization component estimates the pose of the UAV in the satellite geo-referenced database.

![Architecture](assets/project_overview.png)

Here are some examples of localization algorithm:

![sample 01](assets/sample_01.jpg)

In this example, the query image has a sparse set of key points that are matched with the satellite image.
 ![sample 02](assets/sample_02.jpg)


## Requirements

- Docker
  
For Jetson Orin nano:
- JetPack 6.2
- jetson-containers

## Usage

To use the project look over the provided scripts run.sh and run_jetson.sh

In x86

```bash
./run.sh [GSD] [drone_image_dir]
```

In Jetson Orin Nano

```bash
./run_jetson.sh [GSD] [drone_image_dir]
```

## ODM

[ODM](https://github.com/OpenDroneMap/ODM)

## Visual Localization

[visual_localization](https://github.com/TerboucheHacene/visual_localization)

# Acknowledgments

Original repositories forked for this work:
- [ODM](https://github.com/OpenDroneMap/ODM)
- [jetson-containers](https://github.com/dusty-nv/jetson-containers)
- [visual_localization](https://github.com/TerboucheHacene/visual_localization)

The original implementation of the paper can be found [here](https://github.com/TIERS/wildnav). I would like to thank the authors of the paper for making their code available.

I would also like to thank the authors of the SuperPoint/SuperGlue for making their code available. The code as well as the weights can be found [here](https://github.com/magicleap/SuperGluePretrainedNetwork).

Finally, I hope this project will be useful for other researchers and developers who are working on visual localization for UAVs using satellite imagery.

# References

* [Vision-based GNSS-Free Localization for UAVs in the Wild](https://arxiv.org/abs/2210.09727)
* [SuperPoint: Self-Supervised Interest Point Detection and Description](https://arxiv.org/abs/1712.07629)
* [SuperGlue: Learning Feature Matching with Graph Neural Networks](https://arxiv.org/abs/1911.11763)


# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
