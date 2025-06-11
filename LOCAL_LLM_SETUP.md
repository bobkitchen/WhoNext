# Local LLM Integration with Ollama

WhoNext now supports local LLM processing using Ollama, providing privacy-focused AI capabilities alongside OpenAI and Claude.

## 🎯 Benefits of Local LLM

- **Complete Privacy**: All AI processing happens on your device - no data sent to external servers
- **Cost Savings**: No per-token charges for heavy users
- **Offline Capability**: AI features work without internet connection
- **Customization**: Choose from various models optimized for different tasks
- **Speed**: Potentially faster responses depending on your hardware

## 🚀 Quick Setup

### 1. Install Ollama

**Option A: Automatic (Recommended)**
1. Open WhoNext Settings
2. Select "Local LLM (Ollama)" as AI Provider
3. Click "Install Ollama" - this opens the Ollama website
4. Download and install Ollama for macOS

**Option B: Manual Installation**
```bash
# Using Homebrew
brew install ollama

# Or download from https://ollama.ai/download
```

### 2. Start Ollama Service

**Option A: From WhoNext**
1. In Settings, click "Start Ollama" button
2. Ollama will start in the background

**Option B: Manual Start**
```bash
# Start Ollama service
ollama serve
```

### 3. Install AI Models

**From WhoNext (Recommended):**
1. Click "Install Models" in Settings
2. Choose from recommended models:
   - **Llama 3.1 (8B)** - Fast, general-purpose (4.7GB)
   - **LLaVA** - Vision model for LinkedIn PDFs (4.7GB)
   - **Mistral 7B** - Efficient reasoning (4.1GB)
   - **Code Llama** - Code analysis (3.8GB)

**Manual Installation:**
```bash
# Install recommended models
ollama pull llama3.1      # For chat and analysis
ollama pull llava         # For LinkedIn PDF processing
ollama pull mistral       # Alternative chat model
```

## 🔧 Model Configuration

### Chat Models
- **Llama 3.1**: Best overall performance for conversation analysis
- **Mistral**: Good alternative with efficient memory usage
- **Code Llama**: Specialized for technical discussions

### Vision Models (LinkedIn PDF Analysis)
- **LLaVA**: Primary vision model for analyzing LinkedIn PDFs
- Automatically used when processing LinkedIn profile documents

### Model Selection
1. Go to Settings → AI Provider → Local LLM (Ollama)
2. Select your preferred Chat Model from installed models
3. Select Vision Model for LinkedIn PDF processing
4. Models are automatically downloaded when selected

## 🛠️ Advanced Configuration

### Custom Ollama Server
- **Default**: `http://localhost:11434`
- **Custom**: Change in Advanced Settings if running Ollama on different port/server

### Performance Optimization
- **RAM Requirements**: 8GB+ recommended for 7B models, 32GB+ for 70B models
- **Storage**: Each model requires 3-40GB depending on size
- **Apple Silicon**: Optimized for M1/M2/M3 Macs

## 📊 Model Comparison

| Model | Size | RAM Needed | Speed | Quality | Best For |
|-------|------|------------|-------|---------|----------|
| Llama 3.1 (8B) | 4.7GB | 8GB | Fast | High | General chat, analysis |
| Llama 3.1 (70B) | 40GB | 64GB | Slow | Highest | Complex reasoning |
| Mistral 7B | 4.1GB | 8GB | Fast | Good | Efficient processing |
| LLaVA | 4.7GB | 8GB | Medium | Good | Image/PDF analysis |
| Code Llama | 3.8GB | 8GB | Fast | High | Code discussions |

## 🔄 Switching Between Providers

WhoNext seamlessly supports switching between:
- **OpenAI**: Cloud-based, requires API key, highest quality
- **Claude**: Cloud-based, requires API key, excellent reasoning
- **Local LLM**: Privacy-focused, no API key, runs offline

Simply change the AI Provider in Settings - all features work identically.

## 🚨 Troubleshooting

### Ollama Not Starting
```bash
# Check if Ollama is running
ps aux | grep ollama

# Restart Ollama
pkill ollama
ollama serve
```

### Model Download Issues
```bash
# Check available models
ollama list

# Re-download model
ollama pull llama3.1
```

### Performance Issues
- Close other memory-intensive applications
- Use smaller models (7B instead of 70B)
- Ensure sufficient free storage space

### Connection Issues
- Verify Ollama is running: `curl http://localhost:11434/api/tags`
- Check firewall settings
- Restart Ollama service

## 🔍 Features Supported

### ✅ Fully Supported
- Chat interface and insights
- Pre-meeting briefs
- Conversation analysis
- LinkedIn PDF processing (with LLaVA)
- Org chart analysis
- All existing AI workflows

### 🔄 Automatic Fallback
- If Ollama is not running, WhoNext will show helpful error messages
- Easy switching back to cloud providers
- No data loss during provider changes

## 🎛️ Settings Reference

### AI Provider Settings
- **Provider Selection**: Choose between OpenAI, Claude, or Local LLM
- **Model Selection**: Pick chat and vision models from installed options
- **Status Monitoring**: Real-time status of Ollama service
- **Model Management**: Install, update, and remove models

### Advanced Settings
- **Base URL**: Custom Ollama server endpoint
- **Timeout Settings**: Automatic timeout configuration for large models
- **Performance Monitoring**: Model usage and response times

## 🔐 Privacy & Security

### Data Privacy
- **Zero External Transmission**: All processing happens locally
- **No Logging**: Conversations are not logged by Ollama
- **Full Control**: You own and control all AI processing

### Security Benefits
- **No API Keys**: No cloud service credentials required
- **Offline Operation**: Works without internet connection
- **Local Storage**: All models stored on your device

## 📈 Performance Tips

### Optimal Hardware
- **Apple Silicon Macs**: Best performance with unified memory
- **Intel Macs**: Supported but slower performance
- **RAM**: More RAM = larger models and faster processing
- **SSD**: Fast storage improves model loading times

### Model Selection Strategy
1. **Start Small**: Begin with Llama 3.1 (8B) for testing
2. **Add Vision**: Install LLaVA for LinkedIn PDF features
3. **Scale Up**: Try larger models if you have sufficient RAM
4. **Specialize**: Add Code Llama for technical conversations

## 🆘 Support

### Getting Help
1. Check Ollama status in WhoNext Settings
2. Review this documentation
3. Check Ollama logs: `ollama logs`
4. Visit [Ollama Documentation](https://ollama.ai/docs)

### Common Solutions
- **Restart Ollama**: Fixes most connection issues
- **Reinstall Models**: Resolves corrupted model files
- **Check Resources**: Ensure sufficient RAM and storage
- **Update Ollama**: Keep Ollama updated for best performance

---

**Ready to get started?** Open WhoNext Settings and select "Local LLM (Ollama)" as your AI Provider!
