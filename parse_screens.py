import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract class name
    class_match = re.search(r'class\s+([A-Za-z0-9_]+Screen|[A-Za-z0-9_]+View|[A-Za-z0-9_]+Page|[A-Za-z0-9_]+Dashboard)\s+extends', content)
    if not class_match:
        return None

    class_name = class_match.group(1)
    
    # Try to extract a docstring or top-level comment
    purpose = "Main view for " + class_name
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if line.strip().startswith('//') and class_name.lower() in line.lower():
            purpose = line.strip(' /')
            break

    # Extract features/actions (buttons, taps, navigation)
    actions = set()
    
    # Navigations
    navs = re.findall(r'Navigator\.push[^\(]*\([^\,]+,\s*MaterialPageRoute\(\s*builder:\s*\([^\)]*\)\s*=>\s*([A-Za-z0-9_]+)\(', content)
    for nav in navs:
        actions.add(f"Navigates to {nav}")

    # Buttons
    buttons = re.findall(r'(?:ElevatedButton|TextButton|IconButton|SafeIconButton|FloatingActionButton|ListTile)[^;]+?(?:onPressed|onTap):\s*(?:[^\)]*\)\s*(?:=>|\{)|([a-zA-Z0-9_]+))', content)
    
    # Also find text inside buttons if possible
    btn_texts = re.findall(r"Text\('([^']+)'\)", content)
    
    for text in btn_texts[:5]:
        if len(text) < 20:
            actions.add(f"Displays text/action: '{text}'")

    for btn in buttons:
        if isinstance(btn, str) and btn.startswith('_'):
            actions.add(f"Triggers internal action: {btn}")

    if not actions:
        actions.add("Displays standard UI elements for this view")

    return {
        'path': filepath.replace('\\', '/'),
        'name': class_name,
        'purpose': purpose,
        'actions': list(actions)[:8]
    }

print("## Screens & Features")
for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart') and ('screen' in file or 'view' in file or 'page' in file or 'dashboard' in file):
            res = process_file(os.path.join(root, file))
            if res:
                print(f"### {res['name']} ({res['path']})")
                print(f"**Purpose:** {res['purpose']}")
                for action in res['actions']:
                    print(f"- {action}")
                print()
