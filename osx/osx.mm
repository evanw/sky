#define SKEW_GC_MARK_AND_SWEEP
#import <skew.h>

////////////////////////////////////////////////////////////////////////////////

struct FixedArray SKEW_BASE_OBJECT {
  FixedArray(int byteCount) {
    assert(byteCount >= 0);
    _data = new float[byteCount + 3 & ~3];
    _byteCount = byteCount;
  }

  ~FixedArray() {
    delete _data;
  }

  int byteCount() {
    return _byteCount;
  }

  int getByte(int byteIndex) {
    assert(0 <= byteIndex && byteIndex + 1 <= _byteCount);
    return bytesForCPP()[byteIndex];
  }

  void setByte(int byteIndex, int value) {
    assert(0 <= byteIndex && byteIndex + 1 <= _byteCount);
    bytesForCPP()[byteIndex] = value;
  }

  double getFloat(int byteIndex) {
    assert(0 <= byteIndex && byteIndex + 4 <= _byteCount && byteIndex % 4 == 0);
    return _data[byteIndex / 4];
  }

  void setFloat(int byteIndex, double value) {
    assert(0 <= byteIndex && byteIndex + 4 <= _byteCount && byteIndex % 4 == 0);
    _data[byteIndex / 4] = value;
  }

  FixedArray *getRange(int byteIndex, int byteCount) {
    return new FixedArray(this, byteIndex, byteCount);
  }

  void setRange(int byteIndex, FixedArray *array) {
    assert(byteIndex >= 0 && byteIndex + array->_byteCount <= _byteCount);
    assert(byteIndex % 4 == 0);
    memcpy(_data + byteIndex / 4, array->_data, array->_byteCount);
  }

  uint8_t *bytesForCPP() {
    return reinterpret_cast<uint8_t *>(_data);
  }

  #ifdef SKEW_GC_MARK_AND_SWEEP
    virtual void __gc_mark() override {
    }
  #endif

private:
  FixedArray(FixedArray *array, int byteIndex, int byteCount) {
    assert(byteIndex >= 0 && byteCount >= 0 && byteIndex + byteCount <= array->_byteCount);
    assert(byteCount % 4 == 0);
    _data = new float[byteCount / 4];
    _byteCount = byteCount;
    memcpy(_data, array->_data + byteIndex / 4, byteCount);
  }

  float *_data = nullptr;
  int _byteCount = 0;
};

namespace Log {
  void info(const Skew::string &text) {
    #ifndef NDEBUG
      puts(text.c_str());
    #endif
  }

  void warning(const Skew::string &text) {
    #ifndef NDEBUG
      puts(text.c_str());
    #endif
  }

  void error(const Skew::string &text) {
    #ifndef NDEBUG
      puts(text.c_str());
    #endif
  }
}

////////////////////////////////////////////////////////////////////////////////

#import "compiled.cpp"
#import <skew.cpp>
#import <codecvt>
#import <locale>
#import <sys/time.h>
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>

@class AppView;

////////////////////////////////////////////////////////////////////////////////

namespace OpenGL {
  struct Context;

  struct Texture : Graphics::Texture {
    Texture(Graphics::Context *context, Graphics::TextureFormat *format, int width, int height, FixedArray *pixels)
        : _context(context), _format(format), _width(0), _height(0) {
      glGenTextures(1, &_texture);
      glBindTexture(GL_TEXTURE_2D, _texture);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, format->magFilter == Graphics::PixelFilter::NEAREST ? GL_NEAREST : GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, format->minFilter == Graphics::PixelFilter::NEAREST ? GL_NEAREST : GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, format->wrap == Graphics::PixelWrap::REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, format->wrap == Graphics::PixelWrap::REPEAT ? GL_REPEAT : GL_CLAMP_TO_EDGE);
      resize(width, height, pixels);
    }

    ~Texture() {
      glDeleteTextures(1, &_texture);
    }

    unsigned int texture() {
      return _texture;
    }

    virtual Graphics::Context *context() override {
      return _context;
    }

    virtual Graphics::TextureFormat *format() override {
      return _format;
    }

    virtual int width() override {
      return _width;
    }

    virtual int height() override {
      return _height;
    }

    virtual void resize(int width, int height, FixedArray *pixels) override {
      assert(width > 0);
      assert(height > 0);
      assert(pixels == nullptr || pixels->byteCount() == width * height * 4);

      if (width != _width || height != _height) {
        _width = width;
        _height = height;

        glBindTexture(GL_TEXTURE_2D, _texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels != nullptr ? pixels->bytesForCPP() : nullptr);
      }
    }

    virtual void upload(FixedArray *sourcePixels, int targetX, int targetY, int sourceWidth, int sourceHeight) override {
      assert(sourceWidth >= 0);
      assert(sourceHeight >= 0);
      assert(sourcePixels->byteCount() == sourceWidth * sourceHeight * 4);
      assert(targetX >= 0 && targetX + sourceWidth <= _width);
      assert(targetY >= 0 && targetY + sourceHeight <= _height);

      glBindTexture(GL_TEXTURE_2D, _texture);
      glTexSubImage2D(GL_TEXTURE_2D, 0, targetX, targetY, sourceWidth, sourceHeight, GL_RGBA, GL_UNSIGNED_BYTE, sourcePixels->bytesForCPP());
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_context);
        Skew::GC::mark(_format);
      }
    #endif

  private:
    unsigned int _texture = 0;
    Graphics::Context *_context = nullptr;
    Graphics::TextureFormat *_format = nullptr;
    int _width = 0;
    int _height = 0;
  };

  struct Material : Graphics::Material {
    Material(Graphics::Context *context, Graphics::VertexFormat *format, const char *vertexSource, const char *fragmentSource) : _context(context), _format(format) {
      _program = glCreateProgram();
      _vertexShader = _compileShader(GL_VERTEX_SHADER, vertexSource);
      _fragmentShader = _compileShader(GL_FRAGMENT_SHADER, fragmentSource);

      auto attributes = format->attributes();
      for (int i = 0; i < attributes->count(); i++) {
        glBindAttribLocation(_program, i, (*attributes)[i]->name.c_str());
      }

      glLinkProgram(_program);

      int status = 0;
      glGetProgramiv(_program, GL_LINK_STATUS, &status);

      if (!status) {
        char buffer[4096] = {'\0'};
        int length = 0;
        glGetProgramInfoLog(_program, sizeof(buffer), &length, buffer);
        puts(buffer);
        exit(1);
      }
    }

    ~Material() {
      glDeleteProgram(_program);
      glDeleteShader(_vertexShader);
      glDeleteShader(_fragmentShader);
    }

    void prepare() {
      glUseProgram(_program);
      for (const auto &it : _samplers) {
        auto texture = static_cast<Texture *>(it.second);
        glActiveTexture(GL_TEXTURE0 + it.first);
        glBindTexture(GL_TEXTURE_2D, texture != nullptr ? texture->texture() : 0);
      }
    }

    virtual Graphics::Context *context() override {
      return _context;
    }

    virtual Graphics::VertexFormat *format() override {
      return _format;
    }

    virtual void setUniformFloat(Skew::string name, double x) override {
      glUseProgram(_program);
      glUniform1f(_location(name), x);
    }

    virtual void setUniformInt(Skew::string name, int x) override {
      glUseProgram(_program);
      glUniform1i(_location(name), x);
    }

    virtual void setUniformVec2(Skew::string name, double x, double y) override {
      glUseProgram(_program);
      glUniform2f(_location(name), x, y);
    }

    virtual void setUniformVec3(Skew::string name, double x, double y, double z) override {
      glUseProgram(_program);
      glUniform3f(_location(name), x, y, z);
    }

    virtual void setUniformVec4(Skew::string name, double x, double y, double z, double w) override {
      glUseProgram(_program);
      glUniform4f(_location(name), x, y, z, w);
    }

    virtual void setUniformSampler(Skew::string name, Graphics::Texture *texture, int index) override {
      glUseProgram(_program);
      glUniform1i(_location(name), index);
      _samplers[index] = texture;
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_context);
        Skew::GC::mark(_format);
        for (const auto &it : _samplers) {
          Skew::GC::mark(it.second);
        }
      }
    #endif

  private:
    int _location(const Skew::string &name) {
      auto it = _locations.find(name.std_str());
      if (it == _locations.end()) {
        it = _locations.insert(std::make_pair(name.std_str(), glGetUniformLocation(_program, name.c_str()))).first;
      }
      return it->second;
    }

    unsigned int _compileShader(int type, const char *source) {
      auto shader = glCreateShader(type);
      glShaderSource(shader, 1, &source, nullptr);
      glCompileShader(shader);

      int status = 0;
      glGetShaderiv(shader, GL_COMPILE_STATUS, &status);

      if (!status) {
        char buffer[4096] = {'\0'};
        int length = 0;
        glGetShaderInfoLog(shader, sizeof(buffer), &length, buffer);
        puts(buffer);
        exit(1);
      }

      glAttachShader(_program, shader);
      return shader;
    }

    unsigned int _program = 0;
    unsigned int _vertexShader = 0;
    unsigned int _fragmentShader = 0;
    Graphics::Context *_context = nullptr;
    Graphics::VertexFormat *_format = nullptr;
    std::unordered_map<std::string, int> _locations;
    std::unordered_map<int, Graphics::Texture *> _samplers;
  };

  struct RenderTarget : Graphics::RenderTarget {
    RenderTarget(Graphics::Context *context, Graphics::Texture *texture) : _context(context), _texture(texture) {
      glGenFramebuffers(1, &_framebuffer);
    }

    ~RenderTarget() {
      glDeleteFramebuffers(1, &_framebuffer);
    }

    unsigned int framebuffer() {
      return _framebuffer;
    }

    virtual Graphics::Context *context() override {
      return _context;
    }

    virtual Graphics::Texture *texture() override {
      return _texture;
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_context);
        Skew::GC::mark(_texture);
      }
    #endif

  private:
    Graphics::Context *_context = nullptr;
    Graphics::Texture *_texture = nullptr;
    unsigned int _framebuffer = 0;
  };

  struct Context : Graphics::Context {
    ~Context() {
      glDeleteBuffers(1, &_vertexBuffer);
    }

    virtual int width() override {
      return _width;
    }

    virtual int height() override {
      return _height;
    }

    virtual void addContextResetHandler(Skew::FnVoid0 *callback) override {
    }

    virtual void removeContextResetHandler(Skew::FnVoid0 *callback) override {
    }

    virtual void clear(int color) override {
      _updateRenderTargetAndViewport();
      _updateBlendState();

      if (color != _currentClearColor) {
        glClearColor(
          Graphics::RGBA::red(color) / 255.0,
          Graphics::RGBA::green(color) / 255.0,
          Graphics::RGBA::blue(color) / 255.0,
          Graphics::RGBA::alpha(color) / 255.0);
        _currentClearColor = color;
      }

      glClear(GL_COLOR_BUFFER_BIT);
    }

    virtual Graphics::Material *createMaterial(Graphics::VertexFormat *format, Skew::string vertexSource, Skew::string fragmentSource) override {
      std::string precision("precision highp float;");
      auto vertex = vertexSource.std_str();
      auto fragment = fragmentSource.std_str();
      auto v = vertex.find(precision);
      auto f = fragment.find(precision);
      if (v != std::string::npos) vertex = vertex.substr(v + precision.size());
      if (f != std::string::npos) fragment = fragment.substr(f + precision.size());
      return new Material(this, format, vertex.c_str(), fragment.c_str());
    }

    virtual Graphics::Texture *createTexture(Graphics::TextureFormat *format, int width, int height, FixedArray *pixels) override {
      return new Texture(this, format, width, height, pixels);
    }

    virtual Graphics::RenderTarget *createRenderTarget(Graphics::Texture *texture) override {
      return new RenderTarget(this, texture);
    }

    virtual void draw(Graphics::Primitive primitive, Graphics::Material *material, FixedArray *vertices) override {
      if (vertices == nullptr || vertices->byteCount() == 0) {
        return;
      }

      assert(vertices->byteCount() % material->format()->stride() == 0);

      // Update the texture set before preparing the material so uniform samplers can check for that they use different textures
      _updateRenderTargetAndViewport();
      static_cast<Material *>(material)->prepare();

      // Update the vertex buffer before updating the format so attributes can bind correctly
      if (_vertexBuffer == 0) {
        glGenBuffers(1, &_vertexBuffer);
      }
      glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
      glBufferData(GL_ARRAY_BUFFER, vertices->byteCount(), vertices->bytesForCPP(), GL_DYNAMIC_DRAW);
      _updateFormat(material->format());

      // Draw now that everything is ready
      _updateBlendState();
      glDrawArrays(primitive == Graphics::Primitive::TRIANGLES ? GL_TRIANGLES : GL_TRIANGLE_STRIP,
        0, vertices->byteCount() / material->format()->stride());
    }

    virtual void resize(int width, int height) override {
      assert(width >= 0);
      assert(height >= 0);
      _width = width;
      _height = height;
    }

    virtual void setRenderTarget(Graphics::RenderTarget *renderTarget) override {
      _currentRenderTarget = renderTarget;
    }

    virtual void setBlendState(Graphics::BlendOperation source, Graphics::BlendOperation target) override {
      _blendOperations = (int)source | (int)target << 4;
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_currentRenderTarget);
        Skew::GC::mark(_oldRenderTarget);
      }
    #endif

  private:
    void _updateRenderTargetAndViewport() {
      auto renderTarget = _currentRenderTarget;
      int viewportWidth = renderTarget != nullptr ? renderTarget->texture()->width() : _width;
      int viewportHeight = renderTarget != nullptr ? renderTarget->texture()->height() : _height;

      if (_oldRenderTarget != renderTarget) {
        glBindFramebuffer(GL_FRAMEBUFFER, renderTarget != nullptr ? static_cast<RenderTarget *>(renderTarget)->framebuffer() : 0);
        _oldRenderTarget = renderTarget;
      }

      if (viewportWidth != _oldViewportWidth || viewportHeight != _oldViewportHeight) {
        glViewport(0, 0, viewportWidth, viewportHeight);
        _oldViewportWidth = viewportWidth;
        _oldViewportHeight = viewportHeight;
      }
    }

    void _updateBlendState() {
      if (_oldBlendOperations != _blendOperations) {
        int operations = _blendOperations;
        int oldOperations = _oldBlendOperations;
        int source = operations & 0xF;
        int target = operations >> 4;

        assert(_blendOperationMap.count(source));
        assert(_blendOperationMap.count(target));

        // Special-case the blend mode that just writes over the target buffer
        if (operations == COPY_BLEND_OPERATIONS) {
          glDisable(GL_BLEND);
        } else {
          if (oldOperations == COPY_BLEND_OPERATIONS) {
            glEnable(GL_BLEND);
          }

          // Otherwise, use actual blending
          glBlendFunc(_blendOperationMap[source], _blendOperationMap[target]);
        }

        _oldBlendOperations = operations;
      }
    }

    void _updateFormat(Graphics::VertexFormat *format) {
      // Update the attributes
      auto attributes = format->attributes();
      int count = attributes->count();
      for (int i = 0; i < count; i++) {
        auto attribute = (*attributes)[i];
        bool isByte = attribute->type == Graphics::AttributeType::BYTE;
        glVertexAttribPointer(i, attribute->count, isByte ? GL_UNSIGNED_BYTE : GL_FLOAT, isByte, format->stride(), reinterpret_cast<void *>(attribute->byteOffset));
      }

      // Update the attribute count
      while (_attributeCount < count) {
        glEnableVertexAttribArray(_attributeCount);
        _attributeCount++;
      }
      while (_attributeCount > count) {
        _attributeCount--;
        glDisableVertexAttribArray(_attributeCount);
      }
      _attributeCount = count;
    }

    enum {
      COPY_BLEND_OPERATIONS = (int)Graphics::BlendOperation::ONE | (int)Graphics::BlendOperation::ZERO << 4,
    };

    int _width = 0;
    int _height = 0;
    Graphics::RenderTarget *_currentRenderTarget = nullptr;
    Graphics::RenderTarget *_oldRenderTarget = nullptr;
    int _oldViewportWidth = 0;
    int _oldViewportHeight = 0;
    int _oldBlendOperations = COPY_BLEND_OPERATIONS;
    int _blendOperations = COPY_BLEND_OPERATIONS;
    int _currentClearColor = 0;
    int _attributeCount = 0;
    unsigned int _vertexBuffer = 0;

    static std::unordered_map<int, int> _blendOperationMap;
  };

  std::unordered_map<int, int> Context::_blendOperationMap = {
    { (int)Graphics::BlendOperation::ZERO, GL_ZERO },
    { (int)Graphics::BlendOperation::ONE, GL_ONE },

    { (int)Graphics::BlendOperation::SOURCE_COLOR, GL_SRC_COLOR },
    { (int)Graphics::BlendOperation::TARGET_COLOR, GL_DST_COLOR },
    { (int)Graphics::BlendOperation::INVERSE_SOURCE_COLOR, GL_ONE_MINUS_SRC_COLOR },
    { (int)Graphics::BlendOperation::INVERSE_TARGET_COLOR, GL_ONE_MINUS_DST_COLOR },

    { (int)Graphics::BlendOperation::SOURCE_ALPHA, GL_SRC_ALPHA },
    { (int)Graphics::BlendOperation::TARGET_ALPHA, GL_DST_ALPHA },
    { (int)Graphics::BlendOperation::INVERSE_SOURCE_ALPHA, GL_ONE_MINUS_SRC_ALPHA },
    { (int)Graphics::BlendOperation::INVERSE_TARGET_ALPHA, GL_ONE_MINUS_DST_ALPHA },

    { (int)Graphics::BlendOperation::CONSTANT, GL_CONSTANT_COLOR },
    { (int)Graphics::BlendOperation::INVERSE_CONSTANT, GL_ONE_MINUS_CONSTANT_COLOR },
  };
}

////////////////////////////////////////////////////////////////////////////////

namespace OSX {
  template <typename T, void (*F)(T)>
  struct CDeleter {
    void operator () (T ref) {
      if (ref) {
        F(ref);
      }
    }
  };

  template <typename T, typename X, void (*F)(X)>
  using CPtr = std::unique_ptr<typename std::remove_pointer<T>::type, CDeleter<X, F>>;

  template <typename T>
  using CFPtr = CPtr<T, CFTypeRef, CFRelease>;

  using CGColorSpacePtr = CPtr<CGColorSpaceRef, CGColorSpaceRef, CGColorSpaceRelease>;
  using CGContextPtr = CPtr<CGContextRef, CGContextRef, CGContextRelease>;

  struct GlyphProvider : Graphics::GlyphProvider {
    GlyphProvider(Skew::List<Skew::string> *fontNames) : _fontNames(fontNames) {
    }

    virtual void resize(double fontSize) override {
      _fonts.clear();

      // Find the first user-provided font name
      for (const auto &name : *_fontNames) {
        CFPtr<CFStringRef> holder(CFStringCreateWithCString(kCFAllocatorDefault, name.c_str(), kCFStringEncodingUTF8));
        _fonts.emplace_back(CTFontCreateWithName(holder.get(), fontSize, nullptr));

        // Did we find it?
        if (_fonts.back() != nullptr) {
          Log::info("selected font '" + name.std_str() + "'");
          break;
        }

        // Try the next one
        _fonts.pop_back();
        Log::warning("failed to font font '" + name.std_str() + "'");
      }

      // Use the default fixed-pitch font as a fallback
      if (_fonts.empty()) {
        _fonts.emplace_back(CTFontCreateUIFontForLanguage(kCTFontUIFontUserFixedPitch, fontSize, nullptr));
      }

      // Get the font fallback list
      CFPtr<CFArrayRef> appleLanguages((__bridge_retained CFArrayRef)[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"AppleLanguages"]);
      CFPtr<CFArrayRef> defaultCascade(CTFontCopyDefaultCascadeListForLanguages(_fonts.front().get(), appleLanguages.get()));

      // Create a font for each one because Core Text doesn't have a way of querying a whole cascade for a glyph
      for (int i = 0, length = CFArrayGetCount(defaultCascade.get()); i < length; i++) {
        auto descriptor = (CTFontDescriptorRef)CFArrayGetValueAtIndex(defaultCascade.get(), i);
        _fonts.emplace_back(CTFontCreateWithFontDescriptor(descriptor, fontSize, nullptr));
      }
    }

    virtual double advanceWidth(int codePoint) override {
      _findCodePoint(codePoint);
      return CTFontGetAdvancesForGlyphs(_fonts[_cachedFontIndex].get(), kCTFontOrientationDefault, &_cachedGlyph, nullptr, 1);
    }

    virtual Graphics::Glyph *render(int codePoint, double advanceWidth) override {
      _findCodePoint(codePoint);
      const auto &font = _fonts[_cachedFontIndex];
      auto bounds = CTFontGetBoundingRectsForGlyphs(font.get(), kCTFontOrientationDefault, &_cachedGlyph, nullptr, 1);

      // Make sure the context is big enough
      int minX = std::floor(bounds.origin.x) - 1;
      int minY = std::floor(bounds.origin.y - _cachedFontAscent) - 1;
      int maxX = std::ceil(bounds.origin.x + bounds.size.width) + 2;
      int maxY = std::ceil(bounds.origin.y + bounds.size.height - _cachedFontAscent) + 2;
      int width = maxX - minX;
      int height = maxY - minY;
      if (!_context || width > _width || height > _height) {
        _width = std::max(width * 2, _width);
        _height = std::max(height * 2, _height);
        _bytes.resize(_width * _height * 4);
        _context.reset(CGBitmapContextCreate(_bytes.data(), _width, _height, 8, _width * 4, _deviceRGB.get(), kCGImageAlphaPremultipliedLast));
      }

      auto mask = new Graphics::Mask(width, height);

      // Render the glyph three times at different offsets
      for (int i = 0; i < 3; i++) {
        auto position = CGPointMake(-minX + i / 3.0, -minY - _cachedFontAscent);
        CGContextClearRect(_context.get(), CGRectMake(0, 0, width, height));
        CTFontDrawGlyphs(font.get(), &_cachedGlyph, &position, 1, _context.get());

        // Extract the mask (keep in mind CGContext is upside-down)
        auto from = _bytes.data() + (_height - height) * _width * 4 + 3;
        auto to = mask->pixels->bytesForCPP() + i;
        for (int y = 0; y < height; y++, from += (_width - width) * 4) {
          for (int x = 0; x < width; x++, to += 4, from += 4) {
            *to = *from;
          }
        }
      }

      return new Graphics::Glyph(codePoint, mask, -minX, maxY, advanceWidth);
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_fontNames);
      }
    #endif

  private:
    void _findCodePoint(int codePoint) {
      if (_cachedCodePoint == codePoint) {
        return;
      }

      _cachedCodePoint = codePoint;

      uint16_t codeUnits[2] = { 0, 0 };
      int codeUnitCount = 0;

      // The code point must be UTF-16 encoded
      if (codePoint < 0x10000) {
        codeUnits[0] = codePoint;
        codeUnitCount = 1;
      } else {
        codePoint -= 0x10000;
        codeUnits[0] = (codePoint >> 10) + 0xD800;
        codeUnits[1] = (codePoint & ((1 << 10) - 1)) + 0xDC00;
        codeUnitCount = 2;
      }

      // Search the entire font cascade
      for (int i = 0, length = _fonts.size(); i < length; i++) {
        const auto &font = _fonts[i];

        if (CTFontGetGlyphsForCharacters(font.get(), codeUnits, &_cachedGlyph, codeUnitCount)) {
          _cachedFontIndex = i;
          _cachedFontAscent = CTFontGetAscent(font.get());
          return;
        }
      }

      // Give up after reaching the end
      _cachedGlyph = 0;
      _cachedFontIndex = 0;
      _cachedFontAscent = 0;

      Log::warning("failed to find a glyph for code unit " + std::to_string(codePoint));
    }

    // Stuff for rendering
    int _width = 0;
    int _height = 0;
    CGContextPtr _context = nullptr;
    CGColorSpacePtr _deviceRGB = CGColorSpacePtr(CGColorSpaceCreateDeviceRGB());
    std::vector<uint8_t> _bytes;

    // Stuff for font selection
    int _cachedCodePoint = -1;
    int _cachedFontIndex = -1;
    double _cachedFontAscent = 0;
    CGGlyph _cachedGlyph = -1;
    std::vector<CFPtr<CTFontRef>> _fonts;
    Skew::List<Skew::string> *_fontNames;
  };

  struct AppWindow : Editor::Window, private Editor::PixelRenderer {
    AppWindow(NSWindow *window, AppView *appView, Editor::Platform *platform) : _window(window), _appView(appView), _platform(platform) {
      _shortcuts = new Editor::ShortcutMap(platform);
      _translator = new Editor::SemanticToPixelTranslator(this);
      _lastInvalidationTime = platform->nowInSeconds();

      auto fontNames = new Skew::List<Skew::string> { "Menlo-Regular", "Monaco", "Consolas", "CourierNewPSMT" };
      _font = Graphics::Font::create(platform, fontNames, _fontSize);
      _marginFont = Graphics::Font::create(platform, fontNames, _marginFontSize);
    }

    void handleFrame();
    void handleResize();
    void handleKeyEvent(NSEvent *event);
    void handleInsertText(NSString *text);
    void handleMouseEvent(NSEvent *event);
    void handleAction(Editor::Action action);
    void handlePaste();

    void initializeOpenGL() {
      assert(_context == nullptr);
      _context = new OpenGL::Context();

      _solidBatch = new Graphics::SolidBatch(_context);
      _glyphBatch = new Graphics::GlyphBatch(_platform, _context);
      _dropShadow = new Graphics::DropShadow(_context);
      _translator->setTheme(Editor::Theme::XCODE);

      handleResize();
    }

    void setIsActive(bool isActive) {
      _isActive = isActive;
      invalidate();
    }

    virtual Editor::SemanticRenderer *renderer() override {
      return _translator;
    }

    virtual void setView(Editor::View *view) override {
      _view = view;
      if (_view != nullptr) {
        _view->resizeFont(_advanceWidth, _marginAdvanceWidth, _lineHeight);
      }
      handleResize();
    }

    virtual void setTitle(Skew::string title) override {
      [_window setTitle:[NSString stringWithUTF8String:title.c_str()]];
    }

    virtual int width() override {
      return _width;
    }

    virtual int height() override {
      return _height;
    }

    virtual double pixelScale() override {
      return _pixelScale;
    }

    virtual double fontSize() override {
      return _fontSize;
    }

    virtual double lineHeight() override {
      return _lineHeight;
    }

    virtual void invalidate() override {
      _isInvalid = true;
      _lastInvalidationTime = _platform->nowInSeconds();
    }

    virtual void setCursor(Editor::Cursor cursor) override {
      switch (cursor) {
        case Editor::Cursor::ARROW: _cursor = [NSCursor arrowCursor]; break;
        case Editor::Cursor::TEXT: _cursor = [NSCursor IBeamCursor]; break;
      }
    }

    virtual void setDefaultBackgroundColor(int color) override {
    }

    virtual void fillRect(double x, double y, double width, double height, int color) override {
      _glyphBatch->flush();
      _solidBatch->fillRect(x, y, width, height, Graphics::RGBA::premultiplied(color));
    }

    virtual void fillRoundedRect(double x, double y, double width, double height, int color, double radius) override {
      _glyphBatch->flush();
      _solidBatch->fillRoundedRect(x, y, width, height, Graphics::RGBA::premultiplied(color), radius);
    }

    virtual void strokePolyline(Skew::List<double> *coordinates, int color, double thickness) override {
    }

    virtual void renderText(double x, double y, Skew::string text, Editor::Font font, int color) override {
      if (x >= _width || y >= _height || y + _fontSize <= 0) {
        return;
      }

      auto graphicsFont = font == Editor::Font::MARGIN ? _marginFont : _font;

      _solidBatch->flush();
      y += _fontSize - graphicsFont->size;
      color = Graphics::RGBA::premultiplied(color);

      for (const auto &codePoint : std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t>().from_bytes(text.std_str())) {
        x += _glyphBatch->appendGlyph(graphicsFont, codePoint, x, y, color);
      }
    }

    virtual void renderRectShadow(
      double boxX, double boxY, double boxWidth, double boxHeight,
      double clipX, double clipY, double clipWidth, double clipHeight,
      double shadowAlpha, double blurSigma) override {

      _solidBatch->flush();
      _glyphBatch->flush();
      _dropShadow->render(boxX, boxY, boxWidth, boxHeight, clipX, clipY, clipWidth, clipHeight, shadowAlpha, blurSigma);
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_view);
        Skew::GC::mark(_platform);
        Skew::GC::mark(_shortcuts);
        Skew::GC::mark(_translator);
        Skew::GC::mark(_context);
        Skew::GC::mark(_solidBatch);
        Skew::GC::mark(_glyphBatch);
        Skew::GC::mark(_font);
        Skew::GC::mark(_marginFont);
        Skew::GC::mark(_dropShadow);
      }
    #endif

  private:
    int _width = 0;
    int _height = 0;
    double _pixelScale = 0;
    double _fontSize = 12;
    double _marginFontSize = 10;
    double _lineHeight = 16;
    double _advanceWidth = 0;
    double _marginAdvanceWidth = 0;
    bool _needsToBeShown = true;
    double _lastInvalidationTime = 0;
    bool _areCaretsVisible = true;
    bool _isInvalid = true;
    bool _isActive = false;
    NSWindow *_window = nullptr;
    NSCursor *_cursor = [NSCursor arrowCursor];
    AppView *_appView = nullptr;
    Editor::View *_view = nullptr;
    Editor::Platform *_platform = nullptr;
    Editor::ShortcutMap *_shortcuts = nullptr;
    Editor::SemanticToPixelTranslator *_translator = nullptr;
    Graphics::Context *_context = nullptr;
    Graphics::SolidBatch *_solidBatch = nullptr;
    Graphics::GlyphBatch *_glyphBatch = nullptr;
    Graphics::Font *_font = nullptr;
    Graphics::Font *_marginFont = nullptr;
    Graphics::DropShadow *_dropShadow = nullptr;
  };

  struct Platform : Editor::Platform {
    virtual Editor::OperatingSystem operatingSystem() override {
      return Editor::OperatingSystem::OSX;
    }

    virtual Editor::UserAgent userAgent() override {
      return Editor::UserAgent::UNKNOWN;
    }

    virtual double nowInSeconds() override {
      timeval data;
      gettimeofday(&data, nullptr);
      return data.tv_sec + data.tv_usec / 1.0e6;
    }

    virtual Graphics::GlyphProvider *createGlyphProvider(Skew::List<Skew::string> *fontNames) override {
      return new GlyphProvider(fontNames);
    }

    virtual Editor::Window *createWindow() override;

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
      }
    #endif

  private:
    NSRect _boundsForNewWindow() {
      // Determine frame padding
      auto contentRect = NSMakeRect(0, 0, 256, 256);
      auto frameRect = [NSWindow frameRectForContentRect:contentRect styleMask:_styleMask];
      auto framePadding = NSMakeSize(
        NSWidth(frameRect) - NSWidth(contentRect),
        NSHeight(frameRect) - NSHeight(contentRect));

      // Determine content size
      auto screenRect = [[NSScreen mainScreen] visibleFrame];
      auto contentLimits = [NSWindow contentRectForFrameRect:screenRect styleMask:_styleMask];
      _newWindowBounds.size = NSMakeSize(
        std::fmin(800, NSWidth(contentLimits)),
        std::fmin(600, NSHeight(contentLimits)));

      // Center the first window in the screen
      if (_isFirstWindow) {
        _newWindowBounds.origin = NSMakePoint(
          NSMidX(contentLimits) - NSMidX(_newWindowBounds),
          NSMidY(contentLimits) - NSMidY(_newWindowBounds));
        _isFirstWindow = false;
      }

      // Offset subsequent windows
      else {
        auto offset = framePadding.height;
        _newWindowBounds.origin.x += offset;
        _newWindowBounds.origin.y -= offset;

        // Wrap in x
        if (NSMaxX(_newWindowBounds) > NSMaxX(contentLimits)) {
          _newWindowBounds.origin.x = std::fmin(NSMaxX(contentLimits) - NSWidth(_newWindowBounds),
            NSMinX(contentLimits) + std::fmod(NSMinX(_newWindowBounds) - NSMinX(contentLimits), offset));
        }

        // Wrap in y
        if (NSMinY(_newWindowBounds) < NSMinY(contentLimits)) {
          auto y = NSMinY(_newWindowBounds);
          y = NSHeight(contentLimits) - y - NSHeight(_newWindowBounds) + NSMinY(contentLimits);
          y = std::fmod(std::fmod(y, offset) + offset, offset);
          y = NSHeight(contentLimits) - y - NSHeight(_newWindowBounds) + NSMinY(contentLimits);
          _newWindowBounds.origin.y = std::fmax(y, NSMinY(contentLimits));
        }
      }

      return _newWindowBounds;
    }

    bool _isFirstWindow = true;
    NSRect _newWindowBounds = NSZeroRect;
    int _styleMask = NSClosableWindowMask | NSTitledWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
  };
}

////////////////////////////////////////////////////////////////////////////////

@interface AppView : NSOpenGLView <NSWindowDelegate> {
@public
  CVDisplayLinkRef displayLink;
  Skew::Root<OSX::AppWindow> appWindow;
}

@end

@implementation AppView

- (id)initWithFrame:(NSRect)frame window:(NSWindow *)window platform:(Editor::Platform *)platform {
  NSOpenGLPixelFormatAttribute attributes[] = { NSOpenGLPFADoubleBuffer, 0 };
  auto format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];

  if (self = [super initWithFrame:frame pixelFormat:format]) {
    [self setWantsBestResolutionOpenGLSurface:YES];
    appWindow = new OSX::AppWindow(window, self, platform);
  }

  return self;
}

- (void)dealloc {
  CVDisplayLinkRelease(displayLink);
}

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now,
    const CVTimeStamp *outputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *context) {
  [(__bridge AppView *)context performSelectorOnMainThread:@selector(invalidate) withObject:nil waitUntilDone:NO];
  return kCVReturnSuccess;
}

- (void)prepareOpenGL {
  int swap = 1;
  [[self openGLContext] makeCurrentContext];
  [[self openGLContext] setValues:&swap forParameter:NSOpenGLCPSwapInterval];

  CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
  CVDisplayLinkSetOutputCallback(displayLink, &displayLinkCallback, (__bridge void *)self);
  CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink,
    (CGLContextObj)[[self openGLContext] CGLContextObj],
    (CGLPixelFormatObj)[[self pixelFormat] CGLPixelFormatObj]);
  appWindow->initializeOpenGL();
}

- (void)invalidate {
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect {
  appWindow->handleFrame();
}

- (void)windowDidResize:(NSNotification *)notification {
  appWindow->handleResize();
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
  appWindow->handleResize();
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  appWindow->setIsActive(true);
  CVDisplayLinkStart(displayLink);
}

- (void)windowDidResignKey:(NSNotification *)notification {
  appWindow->setIsActive(false);
  CVDisplayLinkStop(displayLink);
}

- (void)keyDown:(NSEvent *)event {
  appWindow->handleKeyEvent(event);
}

- (void)insertText:(NSString *)text {
  appWindow->handleInsertText(text);
}

- (void)mouseDown:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)mouseDragged:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)mouseUp:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)mouseMoved:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)rightMouseDown:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)rightMouseDragged:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)rightMouseUp:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)otherMouseDown:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)otherMouseDragged:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)otherMouseUp:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)scrollWheel:(NSEvent *)event {
  appWindow->handleMouseEvent(event);
}

- (void)undo:(id)sender {
  appWindow->handleAction(Editor::Action::UNDO);
}

- (void)redo:(id)sender {
  appWindow->handleAction(Editor::Action::REDO);
}

- (void)cut:(id)sender {
  appWindow->handleAction(Editor::Action::CUT);
}

- (void)copy:(id)sender {
  appWindow->handleAction(Editor::Action::COPY);
}

- (void)paste:(id)sender {
  appWindow->handleAction(Editor::Action::PASTE);
}

- (void)selectAll:(id)sender {
  appWindow->handleAction(Editor::Action::SELECT_ALL);
}

@end

////////////////////////////////////////////////////////////////////////////////

void OSX::AppWindow::handleFrame() {
  bool areCaretsVisible = _isActive && ((int)((_platform->nowInSeconds() - _lastInvalidationTime) * 2) & 1) == 0;

  // Skip rendering if not invalid
  if (!_isInvalid && areCaretsVisible == _areCaretsVisible) {
    return;
  }

  // Reset render state
  _isInvalid = false;
  _areCaretsVisible = areCaretsVisible;
  _translator->setShowCarets(areCaretsVisible);

  [[_appView openGLContext] makeCurrentContext];

  if (_view) {
    _view->render();
  }

  _solidBatch->flush();
  _glyphBatch->flush();

  [[_appView openGLContext] flushBuffer];

  if (_needsToBeShown) {
    [_window makeKeyAndOrderFront:nil];
    _needsToBeShown = false;
  }

  Skew::GC::collect();
}

void OSX::AppWindow::handleResize() {
  auto bounds = [_appView bounds];
  auto pixelSize = [_appView convertRectToBacking:bounds].size;

  _width = bounds.size.width;
  _height = bounds.size.height;
  _pixelScale = [_window backingScaleFactor];

  [[_appView openGLContext] makeCurrentContext];

  if (_view != nullptr) {
    _view->resize(_width, _height);
  }

  if (_context != nullptr) {
    _context->resize(pixelSize.width, pixelSize.height);
  }

  if (_solidBatch != nullptr) {
    _solidBatch->resize(_width, _height, _pixelScale);
  }

  if (_glyphBatch != nullptr) {
    _glyphBatch->resize(_width, _height, _pixelScale);
  }

  if (_dropShadow != nullptr) {
    _dropShadow->resize(_width, _height);
  }

  _font->resize(_pixelScale);
  _marginFont->resize(_pixelScale);

  if (_view != nullptr) {
    _advanceWidth = _font->glyphProvider->advanceWidth(' ') / _pixelScale;
    _marginAdvanceWidth = _marginFont->glyphProvider->advanceWidth(' ') / _pixelScale;
    _view->resizeFont(_advanceWidth, _marginAdvanceWidth, _lineHeight);
  }
}

static Editor::KeyCode keyCodeFromEvent(NSEvent *event) {
  static std::unordered_map<int, Editor::KeyCode> map = {
    { '.',                       Editor::KeyCode::PERIOD },
    { '0',                       Editor::KeyCode::NUMBER_0 },
    { '1',                       Editor::KeyCode::NUMBER_1 },
    { '2',                       Editor::KeyCode::NUMBER_2 },
    { '3',                       Editor::KeyCode::NUMBER_3 },
    { '4',                       Editor::KeyCode::NUMBER_4 },
    { '5',                       Editor::KeyCode::NUMBER_5 },
    { '6',                       Editor::KeyCode::NUMBER_6 },
    { '7',                       Editor::KeyCode::NUMBER_7 },
    { '8',                       Editor::KeyCode::NUMBER_8 },
    { '9',                       Editor::KeyCode::NUMBER_9 },
    { ';',                       Editor::KeyCode::SEMICOLON },
    { 'a',                       Editor::KeyCode::LETTER_A },
    { 'b',                       Editor::KeyCode::LETTER_B },
    { 'c',                       Editor::KeyCode::LETTER_C },
    { 'd',                       Editor::KeyCode::LETTER_D },
    { 'e',                       Editor::KeyCode::LETTER_E },
    { 'f',                       Editor::KeyCode::LETTER_F },
    { 'g',                       Editor::KeyCode::LETTER_G },
    { 'h',                       Editor::KeyCode::LETTER_H },
    { 'i',                       Editor::KeyCode::LETTER_I },
    { 'j',                       Editor::KeyCode::LETTER_J },
    { 'k',                       Editor::KeyCode::LETTER_K },
    { 'l',                       Editor::KeyCode::LETTER_L },
    { 'm',                       Editor::KeyCode::LETTER_M },
    { 'n',                       Editor::KeyCode::LETTER_N },
    { 'o',                       Editor::KeyCode::LETTER_O },
    { 'p',                       Editor::KeyCode::LETTER_P },
    { 'q',                       Editor::KeyCode::LETTER_Q },
    { 'r',                       Editor::KeyCode::LETTER_R },
    { 's',                       Editor::KeyCode::LETTER_S },
    { 't',                       Editor::KeyCode::LETTER_T },
    { 'u',                       Editor::KeyCode::LETTER_U },
    { 'v',                       Editor::KeyCode::LETTER_V },
    { 'w',                       Editor::KeyCode::LETTER_W },
    { 'x',                       Editor::KeyCode::LETTER_X },
    { 'y',                       Editor::KeyCode::LETTER_Y },
    { 'z',                       Editor::KeyCode::LETTER_Z },
    { 27,                        Editor::KeyCode::ESCAPE },
    { NSCarriageReturnCharacter, Editor::KeyCode::ENTER },
    { NSDeleteCharacter,         Editor::KeyCode::BACKSPACE },
    { NSDeleteFunctionKey,       Editor::KeyCode::DELETE },
    { NSDownArrowFunctionKey,    Editor::KeyCode::ARROW_DOWN },
    { NSEndFunctionKey,          Editor::KeyCode::END },
    { NSHomeFunctionKey,         Editor::KeyCode::HOME },
    { NSLeftArrowFunctionKey,    Editor::KeyCode::ARROW_LEFT },
    { NSPageDownFunctionKey,     Editor::KeyCode::PAGE_DOWN },
    { NSPageUpFunctionKey,       Editor::KeyCode::PAGE_UP },
    { NSRightArrowFunctionKey,   Editor::KeyCode::ARROW_RIGHT },
    { NSUpArrowFunctionKey,      Editor::KeyCode::ARROW_UP },
  };
  auto characters = [event charactersIgnoringModifiers];

  if ([characters length] == 1) {
    auto it = map.find([characters characterAtIndex:0]);

    if (it != map.end()) {
      return it->second;
    }
  }

  return Editor::KeyCode::NONE;
}

static int modifiersFromEvent(NSEvent *event) {
  auto flags = [event modifierFlags];
  return
    ((flags & NSShiftKeyMask) != 0 ? Editor::Modifiers::SHIFT : 0) |
    ((flags & NSCommandKeyMask) != 0 ? Editor::Modifiers::META : 0) |
    ((flags & NSAlternateKeyMask) != 0 ? Editor::Modifiers::ALT : 0) |
    ((flags & NSControlKeyMask) != 0 ? Editor::Modifiers::CONTROL : 0);
}

void OSX::AppWindow::handleKeyEvent(NSEvent *event) {
  if (_view == nullptr) {
    return;
  }

  auto keyCode = keyCodeFromEvent(event);

  if (keyCode != Editor::KeyCode::NONE) {
    auto modifiers = modifiersFromEvent(event);
    auto action = _shortcuts->get(keyCode, modifiers);

    // Keyboard shortcuts take precedence over text insertion
    if (action != Editor::Action::NONE) {
      _view->triggerAction(action);
      return;
    }

    // This isn't handled by interpretKeyEvents for some reason
    if (keyCode == Editor::KeyCode::ENTER && modifiers == 0) {
      _view->insertText("\n");
      return;
    }
  }

  [_appView interpretKeyEvents:@[event]];
}

void OSX::AppWindow::handleInsertText(NSString *text) {
  if (_view != nullptr) {
    _view->insertText([text UTF8String]);
  }
}

static Editor::MouseEvent *mouseEventFromEvent(NSEvent *event) {
  auto point = [event locationInWindow];
  auto height = [[[event window] contentView] bounds].size.height;
  return new Editor::MouseEvent(point.x, height - point.y, modifiersFromEvent(event), [event clickCount]);
}

void OSX::AppWindow::handleMouseEvent(NSEvent *event) {
  if (_view == nullptr) {
    return;
  }

  switch ([event type]) {
    case NSLeftMouseDown:
    case NSOtherMouseDown:
    case NSRightMouseDown: {
      _view->handleMouseDown(mouseEventFromEvent(event));
      break;
    }

    case NSMouseMoved:
    case NSLeftMouseDragged:
    case NSOtherMouseDragged:
    case NSRightMouseDragged: {
      _view->handleMouseMove(mouseEventFromEvent(event));
      break;
    }

    case NSLeftMouseUp:
    case NSOtherMouseUp:
    case NSRightMouseUp: {
      _view->handleMouseUp(mouseEventFromEvent(event));
      break;
    }

    case NSScrollWheel: {
      _view->handleScroll(-[event scrollingDeltaX], -[event scrollingDeltaY]);
      break;
    }
  }

  // Only show the cursor if the mouse is over the window
  if (NSPointInRect([event locationInWindow], [_appView frame])) {
    [_cursor set];
  } else {
    [[NSCursor arrowCursor] set];
  }
}

void OSX::AppWindow::handleAction(Editor::Action action) {
  if (_view == nullptr) {
    return;
  }

  switch (action) {
    case Editor::Action::CUT:
    case Editor::Action::COPY: {
      auto selection = _view->selection()->isEmpty() ? _view->selectionExpandedToLines() : _view->selection();
      auto text = _view->textInSelection(selection);

      auto clipboard = [NSPasteboard generalPasteboard];
      [clipboard clearContents];
      [clipboard setString:[NSString stringWithUTF8String:text.c_str()] forType:NSPasteboardTypeString];

      if (action == Editor::Action::CUT) {
        _view->changeSelection(selection, Editor::ScrollBehavior::DO_NOT_SCROLL);
        _view->insertText("");
      }
      break;
    }

    case Editor::Action::PASTE: {
      auto clipboard = [NSPasteboard generalPasteboard];
      if (auto text = [clipboard stringForType:NSPasteboardTypeString]) {
        _view->insertText([text UTF8String]);
      }
      break;
    }

    default: {
      _view->triggerAction(action);
      break;
    }
  }
}

Editor::Window *OSX::Platform::createWindow() {
  auto bounds = _boundsForNewWindow();
  auto window = [[NSWindow alloc] initWithContentRect:bounds styleMask:_styleMask backing:NSBackingStoreBuffered defer:NO];
  auto appView = [[AppView alloc] initWithFrame:bounds window:window platform:this];

  [window setCollectionBehavior:[window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];
  [window setContentMinSize:NSMakeSize(4, 4)];
  [window setAcceptsMouseMovedEvents:YES];
  [window setDelegate:appView];
  [window setContentView:appView];
  [window makeFirstResponder:appView];

  return appView->appWindow;
}

////////////////////////////////////////////////////////////////////////////////

@interface AppDelegate : NSObject <NSApplicationDelegate> {
  Skew::Root<Editor::App> app;
}

@end

@implementation AppDelegate

- (void)createNewWindow:(id)sender {
  app->createWindow();
}

- (void)openIssueTracker:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/evanw/sky/issues"]];
}

- (void)applicationDidFinishLaunching:(id)sender {
  auto mainMenu = [[NSMenu alloc] init];
  auto name = [[NSProcessInfo processInfo] processName];

  auto appMenu = [[NSMenu alloc] init];
  [[mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:appMenu];
  [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:name] action:@selector(hide:) keyEquivalent:@"h"];
  [[appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"] setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
  [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name] action:@selector(terminate:) keyEquivalent:@"q"];

  auto fileMenu = [[NSMenu alloc] init];
  [fileMenu setTitle:@"File"];
  [[mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:fileMenu];
  [fileMenu addItemWithTitle:@"New" action:@selector(createNewWindow:) keyEquivalent:@"n"];
  [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];

  auto editMenu = [[NSMenu alloc] init];
  [editMenu setTitle:@"Edit"];
  [[mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:editMenu];
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [[editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"] setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

  auto helpMenu = [[NSMenu alloc] init];
  [helpMenu setTitle:@"Help"];
  [[mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:helpMenu];
  [helpMenu addItemWithTitle:@"Issue Tracker" action:@selector(openIssueTracker:) keyEquivalent:@""];

  [[NSApplication sharedApplication] setMainMenu:mainMenu];

  app = new Editor::App(new OSX::Platform());
}

@end

////////////////////////////////////////////////////////////////////////////////

int main() {
  @autoreleasepool {
    auto application = [NSApplication sharedApplication];
    auto delegate = [[AppDelegate alloc] init]; // This must be stored in a local variable because of ARC
    [application setDelegate:delegate];
    [application activateIgnoringOtherApps:YES];
    [application run];
  }
}
