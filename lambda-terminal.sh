#!/usr/bin/env bash
#
# Lambda Terminal Deployment Script
# 
# This script handles all aspects of the Lambda Terminal deployment:
# - JQ layer preparation
# - AWS CLI layer preparation
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
readonly AWS_CLI_VERSION="2.0.30"
readonly AWS_CLI_LAYER_DIR="${LAYERS_DIR}/awscli"
readonly AWS_CLI_BIN_DIR="${AWS_CLI_LAYER_DIR}/bin"
readonly AWS_CLI_DOWNLOAD_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
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

prepare_awscli_layer() {
    log_info "Preparing AWS CLI layer..."
    
    # Create directories
    mkdir -p "${AWS_CLI_LAYER_DIR}/bin"
    
    # Check if we need to install AWS CLI
    if [[ ! -f "${AWS_CLI_BIN_DIR}/aws" || "$1" == "--force" ]]; then
        log_info "Installing AWS CLI..."
        
        # Create temp directory for AWS CLI installation
        local tmp_dir=$(mktemp -d)
        log_info "Created temporary directory: ${tmp_dir}"
        
        # Download AWS CLI
        log_info "Downloading AWS CLI..."
        if ! curl -L "${AWS_CLI_DOWNLOAD_URL}" -o "${tmp_dir}/awscliv2.zip"; then
            log_error "Failed to download AWS CLI"
            rm -rf "${tmp_dir}"
            return 1
        fi
        
        # Unzip AWS CLI
        log_info "Extracting AWS CLI..."
        if ! unzip -q "${tmp_dir}/awscliv2.zip" -d "${tmp_dir}"; then
            log_error "Failed to extract AWS CLI"
            rm -rf "${tmp_dir}"
            return 1
        fi
        
        # Install AWS CLI to layer directory
        log_info "Installing AWS CLI to layer..."
        if ! "${tmp_dir}/aws/install" --bin-dir "${tmp_dir}/origin" --install-dir "${tmp_dir}/origin" --update; then
            log_error "Failed to install AWS CLI"
            rm -rf "${tmp_dir}"
            return 1
        fi
        #Copy dist from origin into bin
        log_info "Copying AWS CLI to layer bin directory..."
        cp -r "${tmp_dir}/origin/v2/${AWS_CLI_VERSION}/dist"/* "${AWS_CLI_BIN_DIR}/"
    
        
        # Cleanup
        log_info "Cleaning up temporary files..."
        rm -rf "${tmp_dir}"
        
        log_success "AWS CLI installation completed"
    else
        log_info "AWS CLI already installed, skipping installation"
    fi
    
    # Verify AWS CLI wrapper script is executable
    if [[ -f "${AWS_CLI_BIN_DIR}/aws" ]]; then
        chmod +x "${AWS_CLI_BIN_DIR}/aws"
        log_success "AWS CLI layer prepared successfully!"
        return 0
    else
        log_error "AWS CLI wrapper script verification failed"
        return 1
    fi
}

test_awscli() {
    log_info "Testing AWS CLI installation..."
    
    if [[ ! -f "${AWS_CLI_BIN_DIR}/aws" ]]; then
        log_error "AWS CLI wrapper script not found"
        return 1
    fi
    
    # Check if the wrapper script is executable
    if [[ ! -x "${AWS_CLI_BIN_DIR}/aws" ]]; then
        log_error "AWS CLI wrapper script is not executable"
        return 1
    fi
    
    # Check if the AWS CLI executable is present in the installation directory
    if [[ ! -d "${AWS_CLI_LAYER_DIR}" ]]; then
        log_error "AWS CLI installation directory not found"
        return 1
    fi
    
    log_info "AWS CLI appears to be properly installed"
    log_success "AWS CLI test completed successfully"
    return 0
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

destroy_with_sam() {
    log_info "Destroying Lambda Terminal resources..."
    
    if ! check_command "sam" "Please install AWS SAM CLI: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html"; then
        return 1
    fi
    
    # Check AWS credentials before destroying
    if ! check_aws_credentials; then
        return 1
    fi
    
    # Get stack name from config or use default
    local stack_name=$(grep stack_name "${SCRIPT_DIR}/samconfig.toml" | cut -d '"' -f 2 || echo "test-terminal")
    
    log_info "Preparing to delete stack: $stack_name"
    
    # Confirm destruction unless --no-prompts is specified
    local no_prompts=false
    for arg in "$@"; do
        if [[ "$arg" == "--no-prompts" ]]; then
            no_prompts=true
            break
        fi
    done
    
    if [[ "$no_prompts" == false ]]; then
        read -p "Are you sure you want to destroy all Lambda Terminal resources? (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Destruction cancelled by user"
            return 0
        fi
    fi
    
    # Filter out our custom --no-prompts flag
    local sam_args=()
    for arg in "$@"; do
        if [[ "$arg" != "--no-prompts" ]]; then
            sam_args+=("$arg")
        fi
    done
    
    if sam delete --stack-name "$stack_name" "${sam_args[@]}"; then
        log_success "Stack deletion completed successfully"
        return 0
    else
        log_error "Stack deletion failed"
        return 1
    fi
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND] [SAM_OPTIONS]

Lambda Terminal management script for AWS Lambda deployment.

OPTIONS:
  -h, --help        Show this help message and exit
  -f, --force       Force update of layers
  -v, --verbose     Enable verbose output

COMMANDS:
  prepare-layer     Prepare the JQ and AWS CLI layers
  build             Build the Lambda Terminal with SAM
  deploy            Deploy to AWS using SAM
  destroy           Destroy deployed AWS resources
  test-jq           Test JQ installation
  test-awscli       Test AWS CLI installation
  all               Run all steps (prepare, build, deploy)

If no COMMAND is provided, 'build' is assumed.
Parameters can be provided in any order.

SAM_OPTIONS:
  Any additional options will be passed directly to the SAM CLI.
  For example, '--guided' for guided deployment.

Examples:
  $0 -h                  # Show help information
  $0 prepare-layer       # Prepare the JQ and AWS CLI layers
  $0 all -f              # Force update of JQ and AWS CLI layers, then build and deploy
  $0 -v build            # Build with verbose logging
  $0 deploy --guided     # Deploy with guided setup (passed to SAM)
  $0 -f deploy --stack-name my-stack    # Force update layers and deploy with custom stack name
  $0 destroy                # Destroy all deployed resources
  $0 destroy --no-prompts   # Destroy all resources without confirmation
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
            prepare-layer|build|deploy|destroy|test-jq|test-awscli|all)
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
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force") && \
            prepare_awscli_layer $([[ "$force_update" == true ]] && echo "--force")
            ;;
        build)
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force") && \
            prepare_awscli_layer $([[ "$force_update" == true ]] && echo "--force") && \
            build_with_sam
            ;;
        deploy)
            check_aws_credentials && \
            deploy_with_sam "${sam_args[@]}"
            ;;
        destroy)
            check_aws_credentials && \
            destroy_with_sam "${sam_args[@]}"
            ;;
        test-jq)
            test_jq
            ;;
        test-awscli)
            test_awscli
            ;;
        all)
            prepare_jq_layer $([[ "$force_update" == true ]] && echo "--force") && \
            prepare_awscli_layer $([[ "$force_update" == true ]] && echo "--force") && \
            test_jq && \
            test_awscli && \
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
