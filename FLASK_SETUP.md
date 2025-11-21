# Flask Proxy Setup Guide

## Overview

The Godot prototype connects to your existing StoryBlocks Flask proxy for AI features. This guide helps you set it up.

## Option 1: Use Existing Flask Proxy

If you already have the Flask proxy running from your StoryBlocks project:

1. **Ensure it's running:**
   ```bash
   cd /path/to/campbell
   python api_proxy.py
   ```

2. **Verify it's accessible:**
   ```bash
   curl http://localhost:5000/api/models
   ```

3. **Done!** The Godot project will connect automatically.

## Option 2: Copy Flask Proxy to Godot Project

If you want a standalone setup:

1. **Copy Flask files:**
   ```bash
   cp /path/to/campbell/api_proxy.py storyblocks_godot/
   cp /path/to/campbell/requirements.txt storyblocks_godot/
   cp /path/to/campbell/.env storyblocks_godot/
   ```

2. **Install dependencies:**
   ```bash
   cd storyblocks_godot
   pip install -r requirements.txt
   ```

3. **Run proxy:**
   ```bash
   python api_proxy.py
   ```

## Configuration

### Environment Variables

Create or edit `.env` file:

```bash
# Required for AI features
XAI_API_KEY=your-xai-api-key-here

# Optional
XAI_API_BASE=https://api.x.ai/v1
FLASK_ENV=development
PORT=5000
MAX_REQUESTS_PER_MINUTE=20
```

### Godot Configuration

If your Flask proxy runs on a different port or host, edit `scripts/ai/ai_client.gd`:

```gdscript
var api_base: String = "http://localhost:5000"  # Change if needed
```

## Testing the Connection

### From Command Line

```bash
# Test text generation
curl -X POST http://localhost:5000/api/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "xai",
    "model": "grok-3",
    "messages": [
      {"role": "user", "content": "Say hello"}
    ]
  }'

# Test image generation
curl -X POST http://localhost:5000/api/images/generations \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "xai",
    "model": "grok-2-image-1212",
    "prompt": "A fantasy character portrait"
  }'
```

### From Godot

The prototype will automatically test the connection on startup. Check the Godot console for:
```
AIClient initialized - API Base: http://localhost:5000
```

## Troubleshooting

### "Connection refused"
- Flask proxy is not running
- Check port 5000 is not in use: `lsof -i :5000`
- Start proxy: `python api_proxy.py`

### "API key invalid"
- Check `.env` file has correct `XAI_API_KEY`
- Verify key at https://console.x.ai

### "CORS errors"
- Flask proxy should handle CORS automatically
- Check `api_proxy.py` has CORS enabled for localhost

### "Rate limit exceeded"
- Increase `MAX_REQUESTS_PER_MINUTE` in `.env`
- Wait 60 seconds and try again

## Running Without AI (Testing Mode)

If you want to test without the Flask proxy:

1. **Disable AI in Godot:**
   Edit `scripts/core/game_manager.gd`:
   ```gdscript
   var ai_enabled: bool = false  # Set to false
   ```

2. **Add manual assets:**
   - Place portraits in `assets/portraits/`
   - Place backgrounds in `assets/backgrounds/`

3. **Run normally** - No Flask proxy needed

## Production Deployment

For production use:

1. **Use environment variables:**
   ```bash
   export XAI_API_KEY=your-key
   export FLASK_ENV=production
   export PORT=5000
   ```

2. **Run with gunicorn:**
   ```bash
   pip install gunicorn
   gunicorn -w 4 -b 0.0.0.0:5000 api_proxy:app
   ```

3. **Or use systemd service:**
   Create `/etc/systemd/system/storyblocks-api.service`:
   ```ini
   [Unit]
   Description=StoryBlocks API Proxy
   After=network.target

   [Service]
   Type=simple
   User=your-user
   WorkingDirectory=/path/to/storyblocks_godot
   Environment="XAI_API_KEY=your-key"
   ExecStart=/usr/bin/python3 api_proxy.py
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```

   Enable and start:
   ```bash
   sudo systemctl enable storyblocks-api
   sudo systemctl start storyblocks-api
   ```

## Security Notes

### Development
- Flask proxy runs on localhost only
- API key in `.env` file (gitignored)
- CORS allows local origins

### Production
- Use HTTPS (reverse proxy with nginx/caddy)
- Restrict CORS to your domain
- Rate limiting enabled
- API key in secure environment variables
- Consider authentication layer

## Next Steps

1. **Test the connection** with curl commands above
2. **Run the Godot prototype** and check console
3. **Generate some content** and verify it works
4. **Customize AI prompts** in game_manager.gd

---

**Need help?** Check the main README.md or StoryBlocks documentation.
