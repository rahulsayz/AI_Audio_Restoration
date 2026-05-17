import xml.etree.ElementTree as ET
import sys
import os

def validate_appcast():
    print("=== Validating Sangeet AI Sparkle Appcast Feed ===")
    appcast_path = "/Users/rahulchaturvedi/AI_Audio_Restoration/updates/appcast.xml"
    
    if not os.path.exists(appcast_path):
        print(f"Error: appcast.xml not found at {appcast_path}")
        sys.exit(1)
        
    try:
        # Parse XML
        tree = ET.parse(appcast_path)
        root = tree.getroot()
        print("✓ appcast.xml parsed successfully (valid XML syntax).")
        
        # Verify namespaces
        namespaces = {
            'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle',
            'dc': 'http://purl.org/dc/elements/1.1/'
        }
        
        # Validate root tag
        if root.tag != 'rss':
            print(f"Error: Root tag must be <rss>, found <{root.tag}>")
            sys.exit(1)
        print("✓ Root tag is <rss>.")
        
        # Find channel
        channel = root.find('channel')
        if channel is None:
            print("Error: <channel> element not found under <rss>.")
            sys.exit(1)
        print("✓ <channel> tag found.")
        
        # Check required channel items
        title = channel.find('title')
        if title is None or not title.text:
            print("Error: Channel <title> is missing or empty.")
            sys.exit(1)
        print(f"✓ Channel Title: '{title.text}'")
        
        # Find update items
        items = channel.findall('item')
        if not items:
            print("Error: No <item> tags found in the appcast feed.")
            sys.exit(1)
        print(f"✓ Found {len(items)} update release item(s).")
        
        # Validate each update item
        for i, item in enumerate(items):
            print(f"\n--- Validating Item #{i+1} ---")
            item_title = item.find('title')
            title_text = item_title.text if item_title is not None else "Unknown Version"
            print(f"Release: {title_text}")
            
            # Check enclosure
            enclosure = item.find('enclosure')
            if enclosure is None:
                print("Error: <enclosure> tag is missing inside <item>.")
                sys.exit(1)
            print("✓ <enclosure> tag is present.")
            
            # Check required attributes
            required_attribs = ['url', '{http://www.andymatuschak.org/xml-namespaces/sparkle}version', 'length', 'type']
            for attr in required_attribs:
                if attr not in enclosure.attrib:
                    clean_attr = attr.split('}')[-1] if '}' in attr else attr
                    print(f"Error: enclosure is missing required attribute '{clean_attr}'.")
                    sys.exit(1)
                
            version = enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}version']
            url = enclosure.attrib['url']
            length = enclosure.attrib['length']
            sig_key = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'
            
            print(f"✓ Target Version: {version}")
            print(f"✓ Download URL: {url}")
            print(f"✓ Length: {length} bytes")
            
            if sig_key in enclosure.attrib:
                sig = enclosure.attrib[sig_key]
                print(f"✓ Cryptographic EdDSA Signature: '{sig}'")
                if len(sig) < 30:
                    print("Error: EdDSA signature looks too short or invalid.")
                    sys.exit(1)
            else:
                print("Error: enclosure is missing 'sparkle:edSignature' attribute.")
                sys.exit(1)
                
        print("\n=== Appcast Feed Validation Successful! (All checks passed) ===")
        
    except ET.ParseError as e:
        print(f"XML Parsing Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected Validation Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    validate_appcast()
