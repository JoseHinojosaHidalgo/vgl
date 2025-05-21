#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage:"
  echo "  Drone GSD > 20cm: $0 <image>"
  echo "  Drone GSD < 20cm: $0 <GSD> <odm_directory>"
  exit 1 # Exit with an error code
}

run_vgl() {
  echo ""
  read -p "Input visual geolocalization directory path (blank for ./vgl_data): " response

  if [ -z "$response" ]; then
    final_dir="./vgl_data"
    echo "No directory path provided. Using default: '$final_dir'"
    mkdir -p "$final_dir/query"
    mkdir -p "$final_dir/map"
    mkdir -p "$final_dir/output"
  else
    final_dir="$response"
    if [ ! -d "$final_dir" ]; then
      echo "Directory '$final_dir' does not exist."
      exit 1
    fi
  fi
  
  cp "$1" "$final_dir/query/"
  
  read -p "Download satellite images? (Enviroment variable MAPTILER_API_KEY must be set) [y/n]: " response
  
  if [[ "$response" == "y" || "$response" == "yes" ]]; then
    echo ""
    echo "Please provide the arguments for createMap.py:"

    read -p "Enter Top-Left Latitude (e.g., 37.300264): " top_left_lat
    read -p "Enter Top-Left Longitude (e.g., -3.688755): " top_left_lon
    read -p "Enter Bottom-Right Latitude (e.g., 37.294684): " bottom_right_lat
    read -p "Enter Bottom-Right Longitude (e.g., -3.676445): " bottom_right_lon
    read -p "Enter Stitch Size (e.g., 8): " stitch_size

    # Validate input (optional but recommended for numbers)
    # Basic numeric check for latitude/longitude/stitch-size
    if ! [[ "$top_left_lat" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]] || \
       ! [[ "$top_left_lon" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]] || \
       ! [[ "$bottom_right_lat" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]] || \
       ! [[ "$bottom_right_lon" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]] || \
       ! [[ "$stitch_size" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input for one or more numeric arguments. Please enter valid numbers."
        exit 1
    fi

    echo ""
    echo "Running docker command with your specified arguments..."

    jetson-containers run \
        -e MAPTILER_API_KEY \
        --rm \
        -v "$final_dir":/app/data \
        ghcr.io/josehinojosahidalgo/jetson_vgl:1.0_orin \
        poetry run python /app/scripts/createMap.py \
        --top-left-lat "$top_left_lat" \
        --top-left-lon "$top_left_lon" \
        --bottom-right-lat "$bottom_right_lat" \
        --bottom-right-lon "$bottom_right_lon" \
        --stitch-size="$stitch_size"
    
    cp "$final_dir/output/stitched/*" "$final_dir/map/"
  elif [[ "$response" == "n" || "$response" == "no" ]]; then
    echo "Assuming correct satellite images already present..."
  else
    echo ""
    echo "Invalid input. Please answer 'y' or 'n'."
    exit 1 # Exit with an error code for invalid input
  fi
  
  # TODO Add x86 cuda option
  jetson-containers run --rm -v "$final_dir":/app/data ghcr.io/josehinojosahidalgo/jetson_vgl:1.0_orin poetry run python /app/scripts/main.py
}

run_odm()  {
  echo ""
  read -p "Use GPU for SIFT extraction? (compatible GPU must be avaliable) [y/n]: " response
  response=${response,,} # Convert input to lowercase

  echo "Running ODM in $DIR1 gpu..."
  jetson-containers run -ti --rm -v "$(dirname "$2")":/datasets ghcr.io/josehinojosahidalgo/odm_orin:1.0 bash /code/run_odm_orin.sh "$(dirname "$2")" "$1" 8000 16000
}

# Check the number of arguments
if [ "$#" -eq 1 ]; then
  # Scenario 1: One argument (image file for altitude > 200m)
  IMAGE_FILE="$1"

  # Basic check if it's a file
  if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: Image file '$IMAGE_FILE' not found."
    usage
  fi

  echo "Processing image: $IMAGE_FILE"
  run_vgl "$IMAGE_FILE"

elif [ "$#" -eq 2 ]; then
  # Scenario 2: Two arguments (altitude and odm_directory for altitude < 200m)
  GSD_EST="$1"
  ODM_DIRECTORY="$2"

  # Check if altitude is a number
  if ! [[ "$GSD_EST" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: GSD must be a number."
    usage
  fi

  # Convert altitude to an integer for comparison
  if [ "$GSD_EST" -ge 20 ]; then
    echo "Error: For GSD >= 20cm, please use the '<image>' usage."
    usage
  fi

  # Check if odm_directory exists and is a directory
  if [ ! -d "$ODM_DIRECTORY" ]; then
    echo "Error: ODM directory '$ODM_DIRECTORY' not found or is not a directory."
    usage
  else
    echo "✓ Directory exists: $ODM_DIRECTORY"
    
    if find "$ODM_DIRECTORY/images" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.mp4" -o -name "*.JPG" -o -name "*.PNG" -o -name "*.MP4" \) -print -quit | grep -q .; then
      echo "Images or video detected in '$ODM_DIRECTORY'"
    else
      echo "No images or video in '$ODM_DIRECTORY' check file format"
      exit 1
    fi
  fi

  echo "  GSD: $GSD_EST cm/pixel"
  echo "  ODM Directory: $ODM_DIRECTORY"
  run_odm "$GSD_EST" "$ODM_DIRECTORY"
  
  ORTHOPHOTO="$ODM_DIRECTORY/odm_orthophoto/odm_orthophoto.tif"
  
  convert "$ORTHOPHOTO" orthophoto.png
  
  echo "Orthophoto saved to ./orthophoto.png"
  read -p "Exit to process or review orthophoto?: [y/n]" response
  response=${response,,} # Convert input to lowercase

  if [[ "$response" == "y" || "$response" == "yes" ]]; then
      echo "Exiting..."
      exit 1
  elif [[ "$response" == "n" || "$response" == "no" ]]; then
      echo "Continuing to visual geolocalization..."
      run_vgl orthophoto.png
  else
      echo ""
      echo "Invalid input. Please answer 'y' or 'n'."
      exit 1 # Exit with an error code for invalid input
  fi

else
  # Incorrect number of arguments
  usage
fi

echo "Finished successfully."
