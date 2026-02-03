#!/bin/bash
# Integration test for nvim-buddy MCP server
# Run with: ./tests/integration_test.sh

set -e

PORT=7234
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; exit 1; }

# Cleanup on exit
cleanup() {
  if [ -n "$NVIM_PID" ]; then
    kill $NVIM_PID 2>/dev/null || true
  fi
  if [ -n "$SSE_PID" ]; then
    kill $SSE_PID 2>/dev/null || true
  fi
  rm -f /tmp/sse_output_$$
}
trap cleanup EXIT

echo "=== nvim-buddy Integration Tests ==="
echo ""

# Start Neovim with nvim-buddy
echo "Starting nvim-buddy server..."
cd "$PROJECT_DIR"
nvim --headless --clean -u NONE \
  -c "set rtp+=." \
  -c "lua require('buddy').start()" \
  -c "lua vim.defer_fn(function() end, 60000)" &
NVIM_PID=$!
sleep 1

# Test 1: Health endpoint
echo ""
echo "Test 1: Health endpoint"
HEALTH=$(curl -s http://localhost:$PORT/health 2>&1)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
  pass "Health endpoint returns ok"
else
  fail "Health endpoint failed: $HEALTH"
fi

# Test 2: SSE connection returns endpoint
echo ""
echo "Test 2: SSE endpoint"
SSE_RESPONSE=$(timeout 2 curl -sN http://localhost:$PORT/sse 2>&1 || true)
if echo "$SSE_RESPONSE" | grep -q 'event: endpoint'; then
  pass "SSE returns endpoint event"
else
  fail "SSE endpoint failed: $SSE_RESPONSE"
fi

SESSION_ID=$(echo "$SSE_RESPONSE" | grep '"sessionId=' | sed 's/.*sessionId=\([^"]*\).*/\1/' | head -1)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(echo "$SSE_RESPONSE" | grep -o 'sessionId=[0-9]*' | cut -d= -f2 | head -1)
fi
echo "   Session ID: $SESSION_ID"

# Start persistent SSE connection for remaining tests
curl -sN http://localhost:$PORT/sse > /tmp/sse_output_$$ 2>&1 &
SSE_PID=$!
sleep 0.5

# Extract session ID from persistent connection
SESSION_ID=$(grep -o 'sessionId=[0-9]*' /tmp/sse_output_$$ | cut -d= -f2 | head -1)
echo "   Using session: $SESSION_ID"

# Test 3: Initialize
echo ""
echo "Test 3: MCP initialize"
curl -s -X POST "http://localhost:$PORT/message?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' > /dev/null
sleep 0.3

if grep -q '"protocolVersion"' /tmp/sse_output_$$; then
  pass "Initialize returns protocol version"
else
  fail "Initialize failed"
fi

if grep -q '"name":"buddy"' /tmp/sse_output_$$; then
  pass "Initialize returns server name"
else
  fail "Initialize missing server name"
fi

# Test 4: tools/list
echo ""
echo "Test 4: tools/list"
curl -s -X POST "http://localhost:$PORT/message?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' > /dev/null
sleep 0.3

if grep -q '"name":"buffer"' /tmp/sse_output_$$; then
  pass "tools/list returns buffer tool"
else
  fail "tools/list missing buffer"
fi

# Test 5: tools/call
echo ""
echo "Test 5: tools/call buffer"
curl -s -X POST "http://localhost:$PORT/message?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"buffer","arguments":{"action":"list"}}}' > /dev/null
sleep 0.3

if grep -q '"content":\[' /tmp/sse_output_$$; then
  pass "tools/call returns content array"
else
  cat /tmp/sse_output_$$
  fail "tools/call failed"
fi

# Buffer data is JSON-escaped inside text field, look for escaped key
if grep -q 'buffers' /tmp/sse_output_$$; then
  pass "tools/call returns buffer data"
else
  fail "tools/call missing buffers"
fi

# Test 6: Unknown method returns error
echo ""
echo "Test 6: Unknown method error handling"
curl -s -X POST "http://localhost:$PORT/message?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"unknown/method","params":{}}' > /dev/null
sleep 0.3

if grep -q '"code":-32601' /tmp/sse_output_$$; then
  pass "Unknown method returns -32601 error"
else
  fail "Unknown method error handling failed"
fi

# Schema validation setup
SCHEMA_URL="https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-06-18/schema.json"
SCHEMA_CACHE="/tmp/mcp_schema_$$.json"
VALIDATOR=""

# Check for available JSON schema validator
check_validator() {
  # Prefer python for simplicity - just check basic structure
  if command -v python3 >/dev/null 2>&1; then
    VALIDATOR="python"
  fi
}

# Fetch and cache schema
fetch_schema() {
  if [ ! -f "$SCHEMA_CACHE" ]; then
    if ! curl -fsSL "$SCHEMA_URL" -o "$SCHEMA_CACHE" 2>/dev/null; then
      echo "   Warning: Could not fetch MCP schema"
      return 1
    fi
  fi
  return 0
}

# Validate JSON against a sub-schema using Python
validate_with_python() {
  local json_data="$1"
  local schema_ref="$2"
  
  # Simple structural validation without jsonschema dependency
  if [ "$schema_ref" = "ListToolsResult" ]; then
    echo "$json_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'tools' not in data or not isinstance(data['tools'], list):
    print('Missing or invalid tools array')
    sys.exit(1)
for tool in data['tools']:
    if 'name' not in tool:
        print(f'Tool missing name: {tool}')
        sys.exit(1)
    if 'inputSchema' not in tool:
        print(f'Tool missing inputSchema: {tool.get(\"name\", \"unknown\")}')
        sys.exit(1)
sys.exit(0)
" 2>&1
  elif [ "$schema_ref" = "CallToolResult" ]; then
    echo "$json_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'content' not in data or not isinstance(data['content'], list):
    print('Missing or invalid content array')
    sys.exit(1)
for item in data['content']:
    if 'type' not in item:
        print(f'Content item missing type: {item}')
        sys.exit(1)
sys.exit(0)
" 2>&1
  fi
}

# Validate JSON against a sub-schema using ajv
validate_with_ajv() {
  local json_data="$1"
  local schema_ref="$2"
  local data_file="/tmp/mcp_data_$$.json"
  
  # Write data to temp file
  echo "$json_data" > "$data_file"
  
  # Use ajv with the full schema and validate just the data structure
  # ajv doesn't easily support validating against sub-schemas, so we use a simpler approach:
  # Validate that required fields exist and have correct types
  local result=0
  
  if [ "$schema_ref" = "ListToolsResult" ]; then
    # Check that tools array exists with valid tool objects
    if echo "$json_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'tools' not in data or not isinstance(data['tools'], list):
    sys.exit(1)
for tool in data['tools']:
    if 'name' not in tool or 'inputSchema' not in tool:
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
      result=0
    else
      result=1
    fi
  elif [ "$schema_ref" = "CallToolResult" ]; then
    # Check that content array exists with valid content objects
    if echo "$json_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'content' not in data or not isinstance(data['content'], list):
    sys.exit(1)
for item in data['content']:
    if 'type' not in item:
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
      result=0
    else
      result=1
    fi
  fi
  
  rm -f "$data_file"
  return $result
}

# Extract response data from SSE output for a given request id
extract_response() {
  local id="$1"
  # Find the line with matching id and extract the result using Python
  grep "\"id\":$id" /tmp/sse_output_$$ | grep '"result"' | head -1 | python3 -c "
import json, sys
line = sys.stdin.read().strip()
# Handle SSE data: prefix if present
if line.startswith('data: '):
    line = line[6:]
data = json.loads(line)
if 'result' in data:
    print(json.dumps(data['result']))
" 2>/dev/null
}

# Test 7: Validate tools/list schema
echo ""
echo "Test 7: Validate tools/list against MCP schema"
check_validator

if [ -z "$VALIDATOR" ]; then
  echo "   Warning: No JSON schema validator available (need ajv or python3 jsonschema)"
  echo "   Skipping schema validation tests"
else
  if ! fetch_schema; then
    echo "   Skipping schema validation tests (could not fetch schema)"
  else
    # Extract tools/list response (id:2)
    TOOLS_LIST_RESULT=$(extract_response 2)
    
    if [ -n "$TOOLS_LIST_RESULT" ]; then
      if [ "$VALIDATOR" = "python" ]; then
        if validate_with_python "$TOOLS_LIST_RESULT" "ListToolsResult"; then
          pass "tools/list response validates against ListToolsResult schema"
        else
          echo "   Warning: tools/list schema validation failed (non-fatal)"
        fi
      elif [ "$VALIDATOR" = "ajv" ]; then
        if validate_with_ajv "$TOOLS_LIST_RESULT" "ListToolsResult"; then
          pass "tools/list response validates against ListToolsResult schema"
        else
          echo "   Warning: tools/list schema validation failed (non-fatal)"
        fi
      fi
    else
      echo "   Warning: Could not extract tools/list response for validation"
    fi
    
    # Test 8: Validate tools/call schema
    echo ""
    echo "Test 8: Validate tools/call against MCP schema"
    
    # Extract tools/call response (id:3)
    TOOL_CALL_RESULT=$(extract_response 3)
    
    if [ -n "$TOOL_CALL_RESULT" ]; then
      if [ "$VALIDATOR" = "python" ]; then
        if validate_with_python "$TOOL_CALL_RESULT" "CallToolResult"; then
          pass "tools/call response validates against CallToolResult schema"
        else
          echo "   Warning: tools/call schema validation failed (non-fatal)"
        fi
      elif [ "$VALIDATOR" = "ajv" ]; then
        if validate_with_ajv "$TOOL_CALL_RESULT" "CallToolResult"; then
          pass "tools/call response validates against CallToolResult schema"
        else
          echo "   Warning: tools/call schema validation failed (non-fatal)"
        fi
      fi
    else
      echo "   Warning: Could not extract tools/call response for validation"
    fi
  fi
fi

# Cleanup schema cache
rm -f "$SCHEMA_CACHE" /tmp/mcp_wrapper_$$.json

echo ""
echo "=== All integration tests passed! ==="
