#!/usr/bin/env python3
import json
import sys

def fix_prompt_format(data):
    """
    Fix the prompt format by combining separate goal and steps objects
    """
    if isinstance(data, dict):
        # Recursively process dictionary values
        return {k: fix_prompt_format(v) for k, v in data.items()}
    
    elif isinstance(data, list):
        fixed_list = []
        i = 0
        
        while i < len(data):
            current = data[i]
            
            # Check if current item is a list with the problematic format
            if isinstance(current, list) and len(current) == 2:
                # Check if first item has only "goal" and second has "steps"
                if (isinstance(current[0], dict) and 
                    len(current[0]) == 1 and 
                    "goal" in current[0] and
                    isinstance(current[1], dict) and
                    "steps" in current[1]):
                    
                    # Combine them into a single object
                    combined = {
                        "goal": current[0]["goal"],
                        **current[1]  # This will include "steps" and any other keys
                    }
                    fixed_list.append(combined)
                else:
                    # Not the problematic format, process recursively
                    fixed_list.append(fix_prompt_format(current))
            else:
                # Process other items recursively
                fixed_list.append(fix_prompt_format(current))
            
            i += 1
        
        return fixed_list
    
    else:
        # Return other types as-is
        return data

def main():
    # Get input and output file paths
    if len(sys.argv) < 2:
        print("Usage: python fix_prompts_json.py <input_json_file> [output_json_file]")
        print("If output file is not specified, will use 'fixed_prompts.json'")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "fixed_prompts.json"
    
    try:
        # Read the JSON file
        with open(input_file, 'r') as f:
            data = json.load(f)
        
        # Fix the format
        fixed_data = fix_prompt_format(data)
        
        # Write the fixed JSON
        with open(output_file, 'w') as f:
            json.dump(fixed_data, f, indent=2)
        
        print(f"Successfully fixed JSON format!")
        print(f"Input: {input_file}")
        print(f"Output: {output_file}")
        
        # Count how many fixes were made
        import re
        with open(input_file, 'r') as f:
            original_content = f.read()
        
        # Count occurrences of the pattern
        pattern = r'\[\s*\{\s*"goal":\s*"[^"]+"\s*\}\s*,\s*\{\s*"steps":'
        matches = len(re.findall(pattern, original_content))
        
        if matches > 0:
            print(f"Fixed approximately {matches} instances of separated goal/steps objects")
        
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{input_file}': {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 