#!/usr/bin/env bash
#
# Lambda Terminal Deployment Script
# 
# This script handles all aspects of the Lambda Terminal deployment:
# - JQ layer preparation
# - Building with SAM
# - Deploying to AWS
# - Testing the environment
#
# Author: Hleb Yarmolchyk
# Date: June 6, 2025
#

set -eo pipefail  # Exit on error, pipe failures

# ===== GLOBALS =====
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly LAYERS_DIR="${SCRIPT_DIR}/layers"
readonly JQ_LAYER_DIR="${LAYERS_DIR}/jq"
readonly JQ_BIN_DIR="${JQ_LAYER_DIR}/bin"
readonly JQ_VERSION="1.8.0"
readonly JQ_DOWNLOAD_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux64"
readonly LOG_FILE="${SCRIPT_DIR}/lambda-terminal-deploy.log"

# ===== UTILITY FUNCTIONS =====

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo -e "[$timestamp] [$level] $message"
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@" >&2
}

log_success() {
    log "SUCCESS" "$@"
}

check_command() {
    local cmd=$1
    local install_guide=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is not installed."
        [[ -n "$install_guide" ]] && log_info "$install_guide"
        return 1
    fi
    return 0
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured properly"
        log_info "Please configure AWS credentials using:"
        log_info "  aws configure"
        return 1
    fi
    log_info "AWS credentials validated successfully"
    return 0
}

# ===== MAIN FUNCTIONS =====

prepare_jq_layer() {
    log_info "Preparing JQ layer..."
    
    # Create directory structure
    mkdir -p "$JQ_BIN_DIR"
    
    # Download jq binary if it doesn't exist or force flag is set
    if [[ ! -f "${JQ_BIN_DIR}/jq" || "$1" == "--force" ]]; then
        log_info "Downloading jq v${JQ_VERSION}..."
        if curl -L "$JQ_DOWNLOAD_URL" -o "${JQ_BIN_DIR}/jq"; then
            chmod +x "${JQ_BIN_DIR}/jq"
            log_success "JQ binary downloaded and made executable"
        else
            log_error "Failed to download JQ binary"
            return 1
        fi
    else
        log_info "JQ binary already exists, skipping download"
    fi
    
    # Verify jq works
    if "${JQ_BIN_DIR}/jq" --version &> /dev/null; then
        log_success "JQ layer prepared successfully!"
        return 0
    else
        log_error "JQ binary verification failed"
        return 1
    fi
}

test_jq() {
    log_info "Testing JQ installation..."
    
    if [[ ! -f "${JQ_BIN_DIR}/jq" ]]; then
        log_error "JQ binary not found"
        return 1
    fi
    
    # Test jq functionality
    local test_result
    test_result=$(echo '{"test":"success"}' | "${JQ_BIN_DIR}/jq" . 2>&1)
    
    if [[ "$test_result" == *'"test": "success"'* ]]; then
        log_success "JQ test completed successfully"
        return 0
    else
        log_error "JQ test failed: $test_result"
        return 1
    fi
}

build_with_sam() {
    log_info "Building with SAM..."
    
    if ! check_command "sam" "Please install AWS SAM CLI: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html"; then
        return 1
    fi
    
    if sam build; then
        log_success "SAM build completed successfully"
        return 0
    else
        log_error "SAM build failed"
        return 1
    fi
}

deploy_with_sam() {
    log_info "Deploying with SAM..."
    
    if ! check_command "sam" "Please install AWS SAM CLI: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html"; then
        return 1
    fi
    
    # Check AWS credentials before deploying
    if ! check_aws_credentials; then
        return 1
    fi
    
    if sam deploy "$@"; then
        log_success "SAM deployment completed successfully"
        
        # Extract and display the Lambda function URL
        local stack_name=$(grep stack_name "${SCRIPT_DIR}/samconfig.toml" | cut -d '"' -f 2 || echo "test-terminal")
        log_info "Lambda Terminal URL:"
        aws cloudformation describe-stacks --stack-name "$stack_name" \
            --query "Stacks[0].Outputs[?OutputKey=='LambdaTerminalUrl'].OutputValue" \
            --output text
        
        return 0
    else
        log_error "SAM deployment failed"
        return 1
    fi
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND] [SAM_OPTIONS]

Lambda Terminal management script for AWS Lambda deployment.

OPTIONS:
  -h, --help        Show this help message and exit
  -f, --force       Force update of JQ layer
  -v, --verbose     Enable verbose output

COMMANDS:
  prepare-layer     Prepare the JQ layer only
  build             Build the Lambda Terminal with SAM
  deploy            Deploy to AWS using SAM
  test-jq           Test JQ installation
  all               Run all steps (prepare, build, deploy)

If no COMMAND is provided, 'build' is assumed.
Parameters can be provided in any order.

SAM_OPTIONS:
  Any additional options will be passed directly to the SAM CLI.
  For example, '--guided' for guided deployment.

Examples:
  $0 -h                  # Show help information
  $0 prepare-layer       # Prepare the JQ layer only
  $0 all -f              # Force update of JQ layer, then build and deploy
  $0 -v build            # Build with verbose logging
  $0 deploy --guided     # Deploy with guided setup (passed to SAM)
  $0 -f deploy --stack-name my-stack    # Force update JQ and deploy with custom stack name
EOF
}

# ===== MAIN SCRIPT =====

main() {
    # Initialize log file
    [[ -f "$LOG_FILE" ]] && mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
    
    log_info "Started Lambda Terminal deployment process"
    
    local force_update=false
    local verbose=false
    local command=""
    local show_help_flag=false
    local sam_args=()
    
    # Parse options - allow parameters in any order
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help_flag=true
                shift
                ;;
            -f|--force)
                force_update=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            prepare-layer|build|deploy|test-jq|all)
                # If we already have a command, add this as a SAM arg instead
                if [[ -n "$command" ]]; then
                    sam_args+=("$1")
                else
                    command="$1"
                fi
                shift
                ;;
            *)
                # Collect remaining args for SAM
                sam_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Show help if requested or no parameters were provided
    if [[ "$show_help_flag" == true || $# -eq 0 && -z "$command" && ${#sam_args[@]} -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    # Set default command if none was provided
    if [[ -z "$command" ]]; then
        command="build"
    fi
    
    # Set up verbose logging if requested
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    # Execute requested command
    case "$command" in
        prepare-layer)
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force")
            ;;
        build)
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force") && \
            build_with_sam
            ;;
        deploy)
            check_aws_credentials && \
            deploy_with_sam "${sam_args[@]}"
            ;;
        test-jq)
            test_jq
            ;;
        all)
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force") && \
            test_jq && \
            build_with_sam && \
            deploy_with_sam "${sam_args[@]}"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log_success "Lambda Terminal deployment process completed successfully"
    else
        log_error "Lambda Terminal deployment process failed"
    fi
    
    return $result
}

# Function to check if script was called with no arguments
print_help_if_no_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Print help if called with no arguments
    [[ $# -eq 0 ]] && show_help && exit 0
    
    main "$@"
fi
