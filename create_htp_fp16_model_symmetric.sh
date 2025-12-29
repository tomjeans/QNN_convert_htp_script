#!/bin/bash

#==============================================================================
# Shell script to convert ONNX model to QNN FP16 format for HTP devices
# using qnn-onnx-converter and qnn-model-lib-generator
# with is_symmetric=true in quantization overrides
# Default target: aarch64-android
#==============================================================================

# Default values
INPUT_ONNX_MODEL=""
OUTPUT_DIR="./output"
MODEL_NAME="qnn_model"
QNN_SDK_ROOT="${QNN_SDK_ROOT:-}"
QNN_ONNX_CONVERTER=""
QNN_MODEL_LIB_GENERATOR=""
TARGET="aarch64-android"
OP_PACKAGES=""
VERBOSE=false
CLEANUP=true
USE_PER_CHANNEL=false
PERCENTILE_CALIBRATION_VALUE=""
INPUT_LIST=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Convert ONNX model to QNN FP16 format for HTP devices (Android)"
    echo "with is_symmetric=true, percentile quantization, and per-channel quantization"
    echo ""
    echo "Required Options:"
    echo "  -i, --input <PATH>          Input ONNX model file path"
    echo ""
    echo "Optional Options:"
    echo "  -o, --output-dir <PATH>     Output directory for QNN model files (default: ./output)"
    echo "  -n, --model-name <NAME>     Base name for output model files (default: qnn_model)"
    echo "  -s, --sdk-root <PATH>       QNN SDK root directory (default: \$QNN_SDK_ROOT env var)"
    echo "  -c, --converter <PATH>      Path to qnn-onnx-converter tool"
    echo "                              (default: \${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-onnx-converter)"
    echo "  -g, --generator <PATH>      Path to qnn-model-lib-generator tool"
    echo "                              (default: \${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator)"
    echo "  -t, --target <TARGET>       Target platform (default: aarch64-android)"
    echo "                              Options: aarch64-android, x86_64-linux-clang, etc."
    echo "  -p, --op-packages <PATH>   Comma-separated list of op package paths"
    echo "  --input-list <PATH>         Path to input list file for quantization calibration"
    echo "  --per-channel              Enable per-channel quantization for convolution weights"
    echo "  --percentile <VALUE>        Percentile calibration value (e.g., 99.99)"
    echo "                              Required for percentile-based quantization"
    echo "  -v, --verbose              Enable verbose output"
    echo "  --no-cleanup               Keep temporary files after conversion"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -i model.onnx -o ./models -n my_model"
    echo "  $0 -i model.onnx -s /path/to/qnn/sdk"
    echo "  $0 -i model.onnx --per-channel --percentile 99.99 --input-list input_list.txt"
    echo "  $0 -i model.onnx -t x86_64-linux-clang  # For x86_64 target"
    echo ""
}

# Function to print error and exit
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Function to print success
print_success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print info
print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to print step
print_step() {
    echo -e "${BLUE}$1${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_ONNX_MODEL="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--model-name)
            MODEL_NAME="$2"
            shift 2
            ;;
        -s|--sdk-root)
            QNN_SDK_ROOT="$2"
            shift 2
            ;;
        -c|--converter)
            QNN_ONNX_CONVERTER="$2"
            shift 2
            ;;
        -g|--generator)
            QNN_MODEL_LIB_GENERATOR="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -p|--op-packages)
            OP_PACKAGES="$2"
            shift 2
            ;;
        --input-list)
            INPUT_LIST="$2"
            shift 2
            ;;
        --per-channel)
            USE_PER_CHANNEL=true
            shift
            ;;
        --percentile)
            PERCENTILE_CALIBRATION_VALUE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$INPUT_ONNX_MODEL" ]]; then
    print_error "Input ONNX model path is required. Use -i or --input option."
    print_usage
    exit 1
fi

# Check if input file exists
if [[ ! -f "$INPUT_ONNX_MODEL" ]]; then
    print_error "Input ONNX model file not found: $INPUT_ONNX_MODEL"
    exit 1
fi

# Set QNN SDK root
if [[ -z "$QNN_SDK_ROOT" ]]; then
    # Try to find from current directory structure
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$SCRIPT_DIR/bin/x86_64-linux-clang" ]]; then
        QNN_SDK_ROOT="$SCRIPT_DIR"
        print_info "Auto-detected QNN_SDK_ROOT: $QNN_SDK_ROOT"
    else
        print_error "QNN_SDK_ROOT not set and cannot be auto-detected. Please set -s option or QNN_SDK_ROOT environment variable."
        exit 1
    fi
fi

# Set tool paths if not provided
if [[ -z "$QNN_ONNX_CONVERTER" ]]; then
    QNN_ONNX_CONVERTER="${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-onnx-converter"
fi

if [[ -z "$QNN_MODEL_LIB_GENERATOR" ]]; then
    QNN_MODEL_LIB_GENERATOR="${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator"
fi

# Check if tools exist
if [[ ! -f "$QNN_ONNX_CONVERTER" ]] && ! command -v "$QNN_ONNX_CONVERTER" &> /dev/null; then
    print_error "qnn-onnx-converter tool not found: $QNN_ONNX_CONVERTER"
    echo "Please ensure the tool exists or specify the full path with -c option"
    exit 1
fi

if [[ ! -f "$QNN_MODEL_LIB_GENERATOR" ]] && ! command -v "$QNN_MODEL_LIB_GENERATOR" &> /dev/null; then
    print_error "qnn-model-lib-generator tool not found: $QNN_MODEL_LIB_GENERATOR"
    echo "Please ensure the tool exists or specify the full path with -g option"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR" || print_error "Failed to create output directory: $OUTPUT_DIR"

# Print configuration
print_info "=========================================="
print_info "QNN ONNX to HTP FP16 Model Conversion"
print_info "with is_symmetric=true"
print_info "=========================================="
echo "Input ONNX Model:      $INPUT_ONNX_MODEL"
echo "Output Directory:      $OUTPUT_DIR"
echo "Model Name:           $MODEL_NAME"
echo "QNN SDK Root:         $QNN_SDK_ROOT"
echo "Converter Tool:       $QNN_ONNX_CONVERTER"
echo "Generator Tool:       $QNN_MODEL_LIB_GENERATOR"
echo "Target Platform:      $TARGET"
echo "Backend:              HTP"
echo "Precision:            FP16"
echo "Symmetric:            true"
if [[ "$USE_PER_CHANNEL" == true ]]; then
    echo "Per-Channel Quant:     Enabled"
fi
if [[ -n "$PERCENTILE_CALIBRATION_VALUE" ]]; then
    echo "Percentile Calibration: $PERCENTILE_CALIBRATION_VALUE"
fi
if [[ -n "$INPUT_LIST" ]]; then
    echo "Input List:           $INPUT_LIST"
fi
if [[ -n "$OP_PACKAGES" ]]; then
    echo "Op Packages:          $OP_PACKAGES"
fi
echo ""

# Step 1: Convert ONNX to QNN format
print_step "Step 1: Converting ONNX model to QNN format (FP16 for HTP with is_symmetric=true)..."

# Warn if percentile is specified without input list
if [[ -n "$PERCENTILE_CALIBRATION_VALUE" ]] && [[ -z "$INPUT_LIST" ]]; then
    print_info "Note: Percentile calibration typically requires --input-list for proper calibration."
fi

# Create quantization overrides file for FP16 with is_symmetric=true
QUANT_OVERRIDES_FILE=$(mktemp /tmp/qnn_quant_overrides_symmetric_XXXXXX.json)

# Create quantization overrides JSON for FP16 with is_symmetric=true
# Include percentile and per-channel settings if specified
{
    echo "{"
    echo "  \"default_activation_quantization\": {"
    echo "    \"quantization_scheme\": \"float16\","
    echo "    \"is_symmetric\": \"True\""
    if [[ -n "$PERCENTILE_CALIBRATION_VALUE" ]]; then
        echo ","
        echo "    \"calibration_method\": \"percentile\","
        echo "    \"percentile_value\": $PERCENTILE_CALIBRATION_VALUE"
    fi
    echo "  },"
    echo "  \"default_weight_quantization\": {"
    echo "    \"quantization_scheme\": \"float16\","
    echo "    \"is_symmetric\": \"True\""
    if [[ "$USE_PER_CHANNEL" == true ]]; then
        echo ","
        echo "    \"per_channel_quantization\": \"True\""
    fi
    echo "  },"
    echo "  \"activation_encodings\": {},"
    echo "  \"param_encodings\": {}"
    echo "}"
} > "$QUANT_OVERRIDES_FILE"

# Output files from converter
CONVERTER_OUTPUT_CPP="${OUTPUT_DIR}/${MODEL_NAME}.cpp"
CONVERTER_OUTPUT_BIN="${OUTPUT_DIR}/${MODEL_NAME}.bin"
CONVERTER_OUTPUT_JSON="${OUTPUT_DIR}/${MODEL_NAME}_net.json"

# Build the conversion command
CONVERT_CMD="$QNN_ONNX_CONVERTER"
CONVERT_CMD="$CONVERT_CMD --input_network $INPUT_ONNX_MODEL"
CONVERT_CMD="$CONVERT_CMD --output_path $CONVERTER_OUTPUT_CPP"
CONVERT_CMD="$CONVERT_CMD --quantization_overrides $QUANT_OVERRIDES_FILE"

# Add input list if provided (required for quantization calibration)
if [[ -n "$INPUT_LIST" ]]; then
    if [[ ! -f "$INPUT_LIST" ]]; then
        print_error "Input list file not found: $INPUT_LIST"
        rm -f "$QUANT_OVERRIDES_FILE"
        exit 1
    fi
    CONVERT_CMD="$CONVERT_CMD --input_list $INPUT_LIST"
fi

# Add per-channel quantization flag if enabled
if [[ "$USE_PER_CHANNEL" == true ]]; then
    CONVERT_CMD="$CONVERT_CMD --use_per_channel_quantization"
fi

# Add op packages if provided
if [[ -n "$OP_PACKAGES" ]]; then
    CONVERT_CMD="$CONVERT_CMD --op_packages $OP_PACKAGES"
fi

# Print the command if verbose
if [[ "$VERBOSE" == true ]]; then
    print_info "Executing command:"
    echo "$CONVERT_CMD"
    echo ""
    print_info "Quantization overrides JSON content:"
    cat "$QUANT_OVERRIDES_FILE"
    echo ""
fi

# Execute the conversion
if eval "$CONVERT_CMD"; then
    print_success "ONNX to QNN conversion completed successfully!"
    
    # Check if output files were created
    if [[ ! -f "$CONVERTER_OUTPUT_CPP" ]]; then
        print_error "Expected output file not found: $CONVERTER_OUTPUT_CPP"
        rm -f "$QUANT_OVERRIDES_FILE"
        exit 1
    fi
    
    # Check for .bin file (may have different name)
    BIN_FILE=$(find "$OUTPUT_DIR" -name "*.bin" -type f | head -n 1)
    if [[ -n "$BIN_FILE" ]]; then
        CONVERTER_OUTPUT_BIN="$BIN_FILE"
    fi
    
    print_info "Generated files:"
    echo "  - $CONVERTER_OUTPUT_CPP"
    if [[ -f "$CONVERTER_OUTPUT_BIN" ]]; then
        echo "  - $CONVERTER_OUTPUT_BIN"
    fi
    if [[ -f "$CONVERTER_OUTPUT_JSON" ]]; then
        echo "  - $CONVERTER_OUTPUT_JSON"
    fi
else
    print_error "ONNX to QNN conversion failed!"
    rm -f "$QUANT_OVERRIDES_FILE"
    exit 1
fi

echo ""

# Step 2: Generate model library
print_step "Step 2: Generating QNN model library..."

# Find the actual .bin file if it exists
if [[ ! -f "$CONVERTER_OUTPUT_BIN" ]]; then
    # Try to find .bin file in output directory
    BIN_FILE=$(find "$OUTPUT_DIR" -name "*.bin" -type f | head -n 1)
    if [[ -n "$BIN_FILE" ]]; then
        CONVERTER_OUTPUT_BIN="$BIN_FILE"
        print_info "Found .bin file: $CONVERTER_OUTPUT_BIN"
    else
        print_info "No .bin file found, generating library without binary weights..."
    fi
fi

# Build the model library generator command
MODEL_LIB_OUTPUT_DIR="${OUTPUT_DIR}/model_libs"
mkdir -p "$MODEL_LIB_OUTPUT_DIR"

GENERATE_CMD="$QNN_MODEL_LIB_GENERATOR"
GENERATE_CMD="$GENERATE_CMD -c $CONVERTER_OUTPUT_CPP"

if [[ -f "$CONVERTER_OUTPUT_BIN" ]]; then
    GENERATE_CMD="$GENERATE_CMD -b $CONVERTER_OUTPUT_BIN"
fi

GENERATE_CMD="$GENERATE_CMD -o $MODEL_LIB_OUTPUT_DIR"
GENERATE_CMD="$GENERATE_CMD -t $TARGET"

# Print the command if verbose
if [[ "$VERBOSE" == true ]]; then
    print_info "Executing command:"
    echo "$GENERATE_CMD"
    echo ""
fi

# Execute the model library generation
if eval "$GENERATE_CMD"; then
    print_success "Model library generation completed successfully!"
    
    # Check for generated library
    MODEL_LIB_FILE="${MODEL_LIB_OUTPUT_DIR}/${TARGET}/libqnn_model.so"
    if [[ -f "$MODEL_LIB_FILE" ]]; then
        FILE_SIZE=$(du -h "$MODEL_LIB_FILE" | cut -f1)
        print_success "Model library created: $MODEL_LIB_FILE"
        print_info "Library size: $FILE_SIZE"
    else
        # Try alternative naming
        ALT_LIB=$(find "$MODEL_LIB_OUTPUT_DIR" -name "*.so" -type f | head -n 1)
        if [[ -n "$ALT_LIB" ]]; then
            FILE_SIZE=$(du -h "$ALT_LIB" | cut -f1)
            print_success "Model library created: $ALT_LIB"
            print_info "Library size: $FILE_SIZE"
        else
            print_info "Model library generation completed, but .so file location may vary."
        fi
    fi
else
    print_error "Model library generation failed!"
    if [[ "$CLEANUP" == true ]]; then
        rm -f "$QUANT_OVERRIDES_FILE"
    fi
    exit 1
fi

# Clean up temporary file
if [[ "$CLEANUP" == true ]]; then
    rm -f "$QUANT_OVERRIDES_FILE"
else
    print_info "Quantization overrides file kept at: $QUANT_OVERRIDES_FILE"
fi

echo ""
print_success "=========================================="
print_success "Conversion completed successfully!"
print_success "=========================================="
print_info "Output directory: $OUTPUT_DIR"
print_info "Model library location: $MODEL_LIB_OUTPUT_DIR/${TARGET}/"
print_info ""
print_info "Quantization settings:"
print_info "  - Precision: FP16"
print_info "  - is_symmetric: True"
if [[ "$USE_PER_CHANNEL" == true ]]; then
    print_info "  - Per-channel quantization: Enabled"
fi
if [[ -n "$PERCENTILE_CALIBRATION_VALUE" ]]; then
    print_info "  - Percentile calibration: $PERCENTILE_CALIBRATION_VALUE"
fi
print_info ""
print_info "To run the model on Android device:"
if [[ "$TARGET" == "aarch64-android" ]]; then
    print_info "  1. Push the model library to Android device:"
    print_info "     adb push ${MODEL_LIB_OUTPUT_DIR}/${TARGET}/libqnn_model.so /data/local/tmp/"
    print_info "  2. Run on device using qnn-net-run:"
    print_info "     adb shell /data/local/tmp/qnn-net-run --backend libQnnHtp.so --model /data/local/tmp/libqnn_model.so --input_list <input_list.txt>"
else
    print_info "  qnn-net-run --backend libQnnHtp.so --model <path_to_libqnn_model.so> --input_list <input_list.txt>"
fi
print_success "Done!"

