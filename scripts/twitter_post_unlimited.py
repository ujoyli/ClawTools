import asyncio
import os
import json
import sys
from twikit import Client

async def main():
    if len(sys.argv) < 3:
        print(json.dumps({"status": "error", "message": "Usage: python twitter_post_unlimited.py <text> <media_path>"}))
        sys.exit(1)

    text = sys.argv[1]
    media_path = sys.argv[2]
    cookie_path = '/root/cookie.json'

    client = Client('en-US')
    
    # Twikit load_cookies expects a specific format. 
    # Let's try to load the JSON provided and set manually.
    try:
        with open(cookie_path, 'r') as f:
            cookies = json.load(f)
        
        cookie_dict = {c['name']: c['value'] for c in cookies}
        # Required for twikit to work correctly
        auth_token = cookie_dict.get('auth_token')
        ct0 = cookie_dict.get('ct0')
        
        if not auth_token:
            print(json.dumps({"status": "error", "message": "Missing auth_token in cookie.json"}))
            sys.exit(1)
            
        client.set_cookies(cookie_dict)
        
        # Twikit also needs these internal state variables sometimes
        # or we can just try to create the tweet.
    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Cookie load error: {str(e)}"}))
        sys.exit(1)

    try:
        # Determine media type
        is_video = media_path.lower().endswith(('.mp4', '.mov', '.avi'))
        
        if media_path and os.path.exists(media_path):
            media_id = await client.upload_media(media_path, wait_for_completion=True)
            # Twikit create_tweet with media_ids
            tweet = await client.create_tweet(text, media_ids=[media_id])
        else:
            tweet = await client.create_tweet(text)
            
        print(json.dumps({
            "status": "success",
            "id": tweet.id,
            "url": f"https://x.com/user/status/{tweet.id}"
        }))
    except Exception as e:
        print(json.dumps({
            "status": "error",
            "message": str(e)
        }))

if __name__ == "__main__":
    asyncio.run(main())
