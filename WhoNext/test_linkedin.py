import urllib.request
import re

# Use a mock user agent to avoid immediate blocking (though unlikely to work on public profiles without cookies)
headers = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'}
url = "https://www.linkedin.com/in/satyanadella" # Example public profile

try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        
    # Look for the code blocks
    code_blocks = re.findall(r'<code[^>]*>(.*?)</code>', html)
    print(f"Found {len(code_blocks)} code blocks")
    
    # Check for voyager data
    for block in code_blocks:
        if "included" in block and "urn:li:fsd_profile" in block:
            print("Found Voyager data block!")
            print(block[:500]) # Print start of block
            break
            
except Exception as e:
    print(f"Error: {e}")
