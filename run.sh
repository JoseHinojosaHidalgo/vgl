#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
readonly DEFAULT_VGL_DIR="./vgl_data"
readonly DEFAULT_STITCH_SIZE=8
readonly DEFAULT_REGISTRY="ghcr.io/josehinojosahidalgo"
readonly DEFAULT_IMAGE_TAG="jetson_vgl:1.0"
readonly VGL_IMAGE="${VGL_REGISTRY:-$DEFAULT_REGISTRY}/${VGL_IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"

# Global flags
INTERACTIVE_MODE=true
USE_GPU=false
DOWNLOAD_SATELLITE=false
SKIP_ORTHOPHOTO_REVIEW=false
VERBOSE=true
DRY_RUN=false

# Configuration variables
VGL_DIR=""
GSD_VALUE=""
ODM_DIR=""
IMAGE_FILE=""
TOP_LEFT_LAT=""
TOP_LEFT_LON=""
BOTTOM_RIGHT_LAT=""
BOTTOM_RIGHT_LON=""
STITCH_SIZE=""

# Logging functions
log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $*" >&2
}

# Function to display usage information
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Visual Geolocalization Tool

USAGE:
    High altitude (GSD > 20cm):
        $SCRIPT_NAME [OPTIONS] <image_file>
    
    Low altitude (GSD ≤ 20cm):
        $SCRIPT_NAME [OPTIONS] <gsd_value> <odm_directory>

OPTIONS:
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose output
    -n, --non-interactive       Run in non-interactive mode
    -d, --dry-run              Show commands without executing
    --vgl-dir DIR              VGL data directory (default: $DEFAULT_VGL_DIR)
    --use-gpu                  Use GPU for ODM processing
    --no-gpu                   Force CPU-only processing
    --download-satellite       Enable satellite image download
    --skip-satellite           Skip satellite image download
    --skip-orthophoto-review   Skip orthophoto review step
    --stitch-size SIZE         Satellite stitch size (default: $DEFAULT_STITCH_SIZE)
    
    Satellite download options (requires --download-satellite):
    --top-left-lat LAT         Top-left latitude
    --top-left-lon LON         Top-left longitude
    --bottom-right-lat LAT     Bottom-right latitude  
    --bottom-right-lon LON     Bottom-right longitude

ENVIRONMENT VARIABLES:
    MAPTILER_API_KEY           Required for satellite image download
    VGL_REGISTRY              Docker registry (default: $DEFAULT_REGISTRY)
    VGL_IMAGE_TAG             Docker image tag (default: $DEFAULT_IMAGE_TAG)

EXAMPLES:
    # High altitude mode with defaults
    $SCRIPT_NAME drone_image.jpg
    
    # Low altitude mode with GPU
    $SCRIPT_NAME --use-gpu 15.5 /path/to/drone_images
    
    # Non-interactive mode with satellite download
    $SCRIPT_NAME --non-interactive --download-satellite \\
        --top-left-lat 37.300264 --top-left-lon -3.688755 \\
        --bottom-right-lat 37.294684 --bottom-right-lon -3.676445 \\
        drone_image.jpg

EOF
    exit "${1:-0}"
}

# Validate numeric input
validate_number() {
    local value="$1"
    local name="$2"
    local allow_negative="${3:-false}"
    
    if [[ "$allow_negative" == "true" ]]; then
        local pattern='^[+-]?[0-9]+([.][0-9]+)?$'
    else
        local pattern='^[0-9]+([.][0-9]+)?$'
    fi
    
    if ! [[ "$value" =~ $pattern ]]; then
        log_error "Invalid $name: '$value'. Must be a valid number."
        return 1
    fi
}

# Validate latitude/longitude
validate_coordinates() {
    validate_number "$TOP_LEFT_LAT" "top-left latitude" true || return 1
    validate_number "$TOP_LEFT_LON" "top-left longitude" true || return 1
    validate_number "$BOTTOM_RIGHT_LAT" "bottom-right latitude" true || return 1
    validate_number "$BOTTOM_RIGHT_LON" "bottom-right longitude" true || return 1
    
    # Basic range validation
    if (( $(echo "$TOP_LEFT_LAT < -90 || $TOP_LEFT_LAT > 90" | bc -l) )); then
        log_error "Top-left latitude must be between -90 and 90"
        return 1
    fi
    
    if (( $(echo "$BOTTOM_RIGHT_LAT < -90 || $BOTTOM_RIGHT_LAT > 90" | bc -l) )); then
        log_error "Bottom-right latitude must be between -90 and 90"
        return 1
    fi
    
    if (( $(echo "$TOP_LEFT_LON < -180 || $TOP_LEFT_LON > 180" | bc -l) )); then
        log_error "Top-left longitude must be between -180 and 180"
        return 1
    fi
    
    if (( $(echo "$BOTTOM_RIGHT_LON < -180 || $BOTTOM_RIGHT_LON > 180" | bc -l) )); then
        log_error "Bottom-right longitude must be between -180 and 180"
        return 1
    fi
}

# Check required dependencies
check_dependencies() {
    local deps=("docker")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or accessible"
        exit 1
    fi
    
    # Check bc for coordinate validation
    if ! command -v bc &> /dev/null && [[ "$DOWNLOAD_SATELLITE" == "true" ]]; then
        log_warn "bc calculator not found. Coordinate validation will be skipped."
    fi
}

# Interactive prompt with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ "$INTERACTIVE_MODE" == "false" ]]; then
        echo "$default"
        return
    fi
    
    read -p "$prompt${default:+ (default: $default)}: " response
    echo "${response:-$default}"
}

# Yes/No prompt with default
prompt_yes_no() {
    local prompt="$1"
    local default="$2" # "y" or "n"
    local response
    
    if [[ "$INTERACTIVE_MODE" == "false" ]]; then
        echo "$default"
        return
    fi
    
    while true; do
        read -p "$prompt [y/n]${default:+ (default: $default)}: " response
        response="${response:-$default}"
        response="${response,,}" # Convert to lowercase
        
        case "$response" in
            y|yes) echo "y"; return ;;
            n|no) echo "n"; return ;;
            *) echo "Please answer 'y' or 'n'." >&2 ;;
        esac
    done
}

# Setup VGL directory structure
setup_vgl_directory() {
    log_info "Setting up VGL directory: $VGL_DIR"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$VGL_DIR"/{query,map,output}
    else
        log_debug "DRY RUN: mkdir -p $VGL_DIR/{query,map,output}"
    fi
    
    if [[ ! -d "$VGL_DIR" && "$DRY_RUN" == "false" ]]; then
        log_error "Failed to create VGL directory: $VGL_DIR"
        exit 1
    fi
}

# Download satellite images
download_satellite_images() {
    log_info "Downloading satellite images..."
    
    # Validate API key
    if [[ -z "${MAPTILER_API_KEY:-}" ]]; then
        log_error "MAPTILER_API_KEY environment variable is required for satellite download"
        exit 1
    fi
    
    # Validate coordinates
    if ! validate_coordinates; then
        exit 1
    fi
    
    local docker_cmd=(
        docker run
        -e MAPTILER_API_KEY
        --rm
        -v "$VGL_DIR:/app/data"
        "$VGL_IMAGE"
        poetry run python /app/scripts/createMap.py
        --top-left-lat "$TOP_LEFT_LAT"
        --top-left-lon "$TOP_LEFT_LON"
        --bottom-right-lat "$BOTTOM_RIGHT_LAT"
        --bottom-right-lon "$BOTTOM_RIGHT_LON"
        --stitch-size="$STITCH_SIZE"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_debug "DRY RUN: ${docker_cmd[*]}"
    else
        log_debug "Executing: ${docker_cmd[*]}"
        "${docker_cmd[@]}" || {
            log_error "Failed to download satellite images"
            exit 1
        }
        
        # Copy stitched images to map directory
        if [[ -d "$VGL_DIR/output/stitched" ]]; then
            cp "$VGL_DIR/output/stitched/"* "$VGL_DIR/map/" 2>/dev/null || true
        fi
    fi
}

# Run visual geolocalization
run_vgl() {
    local input_image="$1"
    
    # Setup VGL directory
    if [[ -z "$VGL_DIR" ]]; then
        VGL_DIR=$(prompt_with_default "VGL directory path" "$DEFAULT_VGL_DIR")
    fi
    
    setup_vgl_directory
    
    # Copy input image to query directory
    log_info "Copying input image to query directory"
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "$input_image" "$VGL_DIR/query/" || {
            log_error "Failed to copy input image"
            exit 1
        }
    else
        log_debug "DRY RUN: cp $input_image $VGL_DIR/query/"
    fi
    
    # Handle satellite images
    if [[ "$DOWNLOAD_SATELLITE" == "true" ]] || 
       [[ "$INTERACTIVE_MODE" == "true" ]]; then
        
        local download_response
        if [[ "$DOWNLOAD_SATELLITE" == "true" ]]; then
            download_response="y"
        else
            download_response=$(prompt_yes_no "Download satellite images? (MAPTILER_API_KEY must be set)" "n")
        fi
        
        if [[ "$download_response" == "y" ]]; then
            # Get coordinates if not provided
            if [[ -z "$TOP_LEFT_LAT" ]]; then
                TOP_LEFT_LAT=$(prompt_with_default "Top-Left Latitude" "37.300264")
                TOP_LEFT_LON=$(prompt_with_default "Top-Left Longitude" "-3.688755")
                BOTTOM_RIGHT_LAT=$(prompt_with_default "Bottom-Right Latitude" "37.294684")
                BOTTOM_RIGHT_LON=$(prompt_with_default "Bottom-Right Longitude" "-3.676445")
                STITCH_SIZE=$(prompt_with_default "Stitch Size" "$DEFAULT_STITCH_SIZE")
            fi
            
            download_satellite_images
        else
            log_info "Assuming satellite images are already present in $VGL_DIR/map/"
        fi
    fi
    
    # Run visual geolocalization
    log_info "Running visual geolocalization..."
    local docker_cmd=(
        docker run --rm
        -v "$VGL_DIR:/app/data"
        "$VGL_IMAGE"
        poetry run python /app/scripts/main.py
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_debug "DRY RUN: ${docker_cmd[*]}"
    else
        log_debug "Executing: ${docker_cmd[*]}"
        "${docker_cmd[@]}" || {
            log_error "Visual geolocalization failed"
            exit 1
        }
    fi
}

# Run ODM processing
run_odm() {
    local gsd="$1"
    local odm_dir="$2"
    
    # Determine GPU usage
    local gpu_response
    if [[ "$USE_GPU" == "true" ]]; then
        gpu_response="y"
    elif [[ "$USE_GPU" == "false" && "$INTERACTIVE_MODE" == "false" ]]; then
        gpu_response="n"
    else
        gpu_response=$(prompt_yes_no "Use GPU for SIFT extraction?" "n")
    fi
    
    local docker_cmd=(docker run -ti --rm -v "$(dirname "$odm_dir"):/datasets")
    local odm_image="opendronemap/odm"
    
    if [[ "$gpu_response" == "y" ]]; then
        log_info "Running ODM with GPU acceleration..."
        docker_cmd+=(--gpus all)
        odm_image="opendronemap/odm:gpu"
    else
        log_info "Running ODM with CPU..."
    fi
    
    docker_cmd+=(
        "$odm_image"
        --project-path /datasets
        "$(basename "$odm_dir")"
        --orthophoto-resolution="$gsd"
        --fast-orthophoto
        --skip-band-alignment
        --skip-report
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_debug "DRY RUN: ${docker_cmd[*]}"
    else
        log_debug "Executing: ${docker_cmd[*]}"
        "${docker_cmd[@]}" || {
            log_error "ODM processing failed"
            exit 1
        }
    fi
}

# Convert and review orthophoto
process_orthophoto() {
    local odm_dir="$1"
    local orthophoto="$odm_dir/odm_orthophoto/odm_orthophoto.tif"
    local output_png="orthophoto.png"
    
    if [[ ! -f "$orthophoto" ]]; then
        log_error "Orthophoto not found: $orthophoto"
        exit 1
    fi
    
    log_info "Converting orthophoto to PNG..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if command -v convert &> /dev/null; then
            convert "$orthophoto" "$output_png" || {
                log_error "Failed to convert orthophoto"
                exit 1
            }
        else
            log_warn "ImageMagick 'convert' not found. Using Docker alternative..."
            docker run --rm -v "$PWD:/work" -w /work dpokidov/imagemagick \
                convert "$orthophoto" "$output_png" || {
                log_error "Failed to convert orthophoto using Docker"
                exit 1
            }
        fi
    else
        log_debug "DRY RUN: convert $orthophoto $output_png"
    fi
    
    log_info "Orthophoto saved to $output_png"
    
    # Review orthophoto
    if [[ "$SKIP_ORTHOPHOTO_REVIEW" == "false" && "$INTERACTIVE_MODE" == "true" ]]; then
        local review_response
        review_response=$(prompt_yes_no "Exit to process or review orthophoto?" "n")
        
        if [[ "$review_response" == "y" ]]; then
            log_info "Exiting for orthophoto review..."
            exit 0
        fi
    fi
    
    echo "$output_png"
}

# Validate ODM directory
validate_odm_directory() {
    local odm_dir="$1"
    
    if [[ ! -d "$odm_dir" ]]; then
        log_error "ODM directory '$odm_dir' not found or is not a directory"
        return 1
    fi
    
    if [[ ! -d "$odm_dir/images" ]]; then
        log_error "Images directory '$odm_dir/images' not found"
        return 1
    fi
    
    # Check for supported image/video formats
    local image_patterns=("*.jpg" "*.jpeg" "*.png" "*.JPG" "*.JPEG" "*.PNG" "*.mp4" "*.MP4")
    local found_images=false
    
    for pattern in "${image_patterns[@]}"; do
        if compgen -G "$odm_dir/images/$pattern" > /dev/null 2>&1; then
            found_images=true
            break
        fi
    done
    
    if [[ "$found_images" == "false" ]]; then
        log_error "No supported images or videos found in '$odm_dir/images'"
        log_error "Supported formats: ${image_patterns[*]}"
        return 1
    fi
    
    log_info "✓ ODM directory validated: $odm_dir"
    return 0
}

# Parse command line arguments

parse_arguments() {
	while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage 0
                ;;
            -q|--quiet)
                VERBOSE=false
                shift
                ;;
            -n|--non-interactive)
                INTERACTIVE_MODE=false
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --vgl-dir)
                VGL_DIR="$2"
                shift 2
                ;;
            --use-gpu)
                USE_GPU=true
                shift
                ;;
            --no-gpu)
                USE_GPU=false
                shift
                ;;
            --download-satellite)
                DOWNLOAD_SATELLITE=true
                shift
                ;;
            --skip-satellite)
                DOWNLOAD_SATELLITE=false
                shift
                ;;
            --skip-orthophoto-review)
                SKIP_ORTHOPHOTO_REVIEW=true
                shift
                ;;
            --stitch-size)
                STITCH_SIZE="$2"
                validate_number "$STITCH_SIZE" "stitch size" false || exit 1
                shift 2
                ;;
            --top-left-lat)
                TOP_LEFT_LAT="$2"
                shift 2
                ;;
            --top-left-lon)
                TOP_LEFT_LON="$2"
                shift 2
                ;;
            --bottom-right-lat)
                BOTTOM_RIGHT_LAT="$2"
                shift 2
                ;;
            --bottom-right-lon)
                BOTTOM_RIGHT_LON="$2"
                shift 2
                ;;
            --version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage 1
                ;;
            *)
                # Positional arguments
                if [[ -z "$IMAGE_FILE" && -z "$GSD_VALUE" ]]; then
                    # First positional argument
                    if [[ -f "$1" ]]; then
                        IMAGE_FILE="$1"
                    elif validate_number "$1" "GSD" false 2>/dev/null; then
                        GSD_VALUE="$1"
                    else
                        log_error "First argument must be either an image file or GSD value"
                        usage 1
                    fi
                elif [[ -n "$GSD_VALUE" && -z "$ODM_DIR" ]]; then
                    # Second positional argument when first was GSD
                    ODM_DIR="$1"
                else
                    log_error "Too many positional arguments"
                    usage 1
                fi
                shift
                ;;
        esac
    done
    
    # Set default values
    [[ -z "$VGL_DIR" ]] && VGL_DIR="$DEFAULT_VGL_DIR"
    [[ -z "$STITCH_SIZE" ]] && STITCH_SIZE="$DEFAULT_STITCH_SIZE"

	log_info "Arguments parsed"
}

# Main function
main() {
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    
    parse_arguments "$@"
    
    # Validation
    if [[ -z "$IMAGE_FILE" && -z "$GSD_VALUE" ]]; then
        log_error "No input provided. Use --help for usage information."
        usage 1
    fi
    
    check_dependencies

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No commands will be executed"
    fi
    
    # High altitude mode (single image)
    if [[ -n "$IMAGE_FILE" ]]; then
        if [[ ! -f "$IMAGE_FILE" ]]; then
            log_error "Image file '$IMAGE_FILE' not found"
            exit 1
        fi
        
        log_info "High altitude mode: processing image '$IMAGE_FILE'"
        run_vgl "$IMAGE_FILE"
        
    # Low altitude mode (ODM + VGL)
    elif [[ -n "$GSD_VALUE" ]]; then
        if [[ -z "$ODM_DIR" ]]; then
            log_error "ODM directory required when GSD is specified"
            usage 1
        fi
        
        # Validate GSD
        if (( $(echo "$GSD_VALUE >= 20" | bc -l) )); then
            log_error "For GSD >= 20cm, use high altitude mode with image file"
            usage 1
        fi
        
        # Validate ODM directory
        if ! validate_odm_directory "$ODM_DIR"; then
            exit 1
        fi
        
        log_info "Low altitude mode: GSD=$GSD_VALUE cm/pixel, ODM directory='$ODM_DIR'"
        
        # Run ODM
        run_odm "$GSD_VALUE" "$ODM_DIR"
        
        # Process orthophoto
        orthophoto_png=$(process_orthophoto "$ODM_DIR")
        
        # Run VGL on generated orthophoto
        log_info "Running visual geolocalization on generated orthophoto"
        run_vgl "$orthophoto_png"
    fi
    
    log_info "Processing completed successfully!"
}

# Run main function with all arguments
main "$@"