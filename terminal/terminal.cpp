#define SKEW_GC_MARK_AND_SWEEP
#include <skew.h>

namespace Log {
  void info(const Skew::string &text) {}
  void warning(const Skew::string &text) {}
  void error(const Skew::string &text) {}
}

#include "compiled.cpp"
#include <skew.cpp>
#include <locale.h>

#define _XOPEN_SOURCE_EXTENDED
#include <ncurses.h>

////////////////////////////////////////////////////////////////////////////////

enum {
  SKY_COLOR_COMMENT = 1,
  SKY_COLOR_CONSTANT = 2,
  SKY_COLOR_KEYWORD = 3,
  SKY_COLOR_MARGIN = 4,
  SKY_COLOR_SELECTED = 5,
  SKY_COLOR_STRING = 6,
};

// Using wchar_t for unicode was the worst idea ever
void codePointToWchars(int codePoint, cchar_t &buffer) {
  memset(buffer.chars, 0, sizeof(buffer.chars));

  // UTF-32
  if (sizeof(wchar_t) == 4) {
    buffer.chars[0] = codePoint;
  }

  // UTF-16
  else if (sizeof(wchar_t) == 2) {
    if (codePoint < 0x10000) {
      buffer.chars[0] = codePoint;
    } else {
      buffer.chars[0] = ((codePoint - 0x10000) >> 10) + 0xD800;
      buffer.chars[1] = ((codePoint - 0x10000) & ((1 << 10) - 1)) + 0xDC00;
    }
  }

  // UTF-8
  else {
    static_assert(sizeof(wchar_t) == 2 || sizeof(wchar_t) == 4, "unsupported platform");
  }
}

namespace Terminal {
  struct FontInstance : UI::FontInstance {
    FontInstance(UI::Font font) : _font(font) {
    }

    virtual UI::Font font() override {
      return _font;
    }

    virtual double size() override {
      return 1;
    }

    virtual double lineHeight() override {
      return 1;
    }

    // A single character can actually take up multiple cells in the terminal
    // (or no cells at all if libc decides it doesn't feel like printing it)
    virtual double advanceWidth(int codePoint) override {
      auto it = _advanceWidths.find(codePoint);
      if (it != _advanceWidths.end()) {
        return it->second;
      }
      cchar_t buffer;
      codePointToWchars(codePoint, buffer);
      return _advanceWidths[codePoint] = std::max(0, wcswidth(buffer.chars, sizeof(buffer.chars) / sizeof(*buffer.chars)));
    }

    virtual Graphics::Glyph *renderGlyph(int codePoint) override {
      return nullptr;
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        UI::FontInstance::__gc_mark();
      }
    #endif

  private:
    UI::Font _font = {};
    std::unordered_map<int, int> _advanceWidths;
  };

  struct Host : UI::Platform, UI::Window, private UI::SemanticRenderer {
    struct ClipRect {
      int minX;
      int minY;
      int maxX;
      int maxY;
    };

    void triggerFrame() {
      if (_delegate != nullptr) {
        _delegate->triggerFrame();
      }
    }

    void handleResize() {
      _width = getmaxx(stdscr);
      _height = getmaxy(stdscr);
      _handleResize(new Vector(_width, _height), 1);
    }

    void render() {
      erase();
      assert(_clipRectStack.empty());
      _clipRectStack.push_back(ClipRect{0, 0, _width, _height});
      _root->render();
      _clipRectStack.pop_back();
      refresh();
      Skew::GC::collect();
    }

    void triggerAction(Editor::Action action) {
      switch (action) {
        case Editor::Action::CUT:
        case Editor::Action::COPY:
        case Editor::Action::PASTE: {
          auto text = _readFromClipboard();
          auto kind =
            action == Editor::Action::CUT ? UI::EventKind::CLIPBOARD_CUT :
            action == Editor::Action::COPY ? UI::EventKind::CLIPBOARD_COPY :
            UI::EventKind::CLIPBOARD_PASTE;
          auto event = new UI::ClipboardEvent(kind, viewWithFocus(), text);
          dispatchEvent(event);
          if (event->text != text) {
            _writeToClipboard(event->text.std_str());
          }
          break;
        }

        default: {
          if (_delegate != nullptr) {
            _delegate->triggerAction(action);
          }
          break;
        }
      }
    }

    void insertUTF8(char c) {
      dispatchEvent(new UI::ClipboardEvent(UI::EventKind::CLIPBOARD_PASTE, viewWithFocus(), std::string(1, c)));
    }

    virtual UI::OperatingSystem operatingSystem() override {
      return UI::OperatingSystem::UNKNOWN;
    }

    virtual UI::UserAgent userAgent() override {
      return UI::UserAgent::UNKNOWN;
    }

    virtual double nowInSeconds() override {
      timeval data;
      gettimeofday(&data, nullptr);
      return data.tv_sec + data.tv_usec / 1.0e6;
    }

    virtual UI::Window *createWindow() override {
      return this;
    }

    virtual UI::SemanticRenderer *renderer() override {
      return this;
    }

    virtual UI::Platform *platform() override {
      return this;
    }

    virtual UI::FontInstance *fontInstance(UI::Font font) override {
      auto it = _fontInstances.find((int)font);
      if (it != _fontInstances.end()) {
        return it->second;
      }
      return _fontInstances[(int)font] = new FontInstance(font);
    }

    virtual void setFont(UI::Font font, Skew::List<Skew::string> *names, double size, double height) override {
    }

    virtual void setTitle(Skew::string title) override {
    }

    virtual void setTheme(UI::Theme *theme) override {
    }

    virtual void setCursor(UI::Cursor cursor) override {
    }

    virtual void renderView(UI::View *view) override {
      assert(!_clipRectStack.empty());
      auto clip = _clipRectStack.back();
      auto bounds = view->bounds();

      _clipRectStack.push_back(ClipRect{
        clip.minX + std::max((int)bounds->x, 0),
        clip.minY + std::max((int)bounds->y, 0),
        clip.minX + std::min((int)(bounds->x + bounds->width), clip.maxX - clip.minX),
        clip.minY + std::min((int)(bounds->y + bounds->height), clip.maxY - clip.minY),
      });
      view->render();
      _clipRectStack.pop_back();
    }

    virtual void renderRect(double x, double y, double width, double height, UI::Color color) override {
      assert(x == (int)x);
      assert(y == (int)y);
      assert(width == (int)width);
      assert(height == (int)height);

      auto clip = _clipRectStack.back();
      x += clip.minX;
      y += clip.minY;

      if (color == UI::Color::BACKGROUND_SELECTED || color == UI::Color::BACKGROUND_MARGIN) {
        int minX = std::max(clip.minX, (int)x);
        int minY = std::max(clip.minY, (int)y);
        int maxX = std::min(clip.maxX, (int)(x + width));
        int maxY = std::min(clip.maxY, (int)(y + height));
        int n = std::max(0, maxX - minX);
        cchar_t buffer;

        for (int y = minY; y < maxY; y++) {
          for (int x = 0; x < n; x++) {
            if (color == UI::Color::BACKGROUND_SELECTED) {
              mvin_wch(y, minX + x, &buffer);
              buffer.attr = (buffer.attr & ~A_COLOR) | COLOR_PAIR(SKY_COLOR_SELECTED);
            } else {
              buffer = {};
              buffer.chars[0] = ' ';
            }
            mvadd_wch(y, minX + x, &buffer);
          }
        }
      }
    }

    virtual void renderCaret(double x, double y, UI::Color color) override {
      assert(x == (int)x);
      assert(y == (int)y);

      auto clip = _clipRectStack.back();
      x += clip.minX;
      y += clip.minY;

      if (x < clip.minX || y < clip.minY || x >= clip.maxX || y >= clip.maxY) {
        return;
      }

      // Underline the character at (x, y)
      cchar_t c;
      mvin_wch(y, x, &c);
      c.attr |= A_UNDERLINE;
      mvadd_wch(y, x, &c);
    }

    virtual void renderSquiggle(double x, double y, double width, double height, UI::Color color) override {
    }

    virtual void renderRightwardShadow(double x, double y, double width, double height) override {
    }

    virtual void renderText(double x, double y, Skew::string text, UI::Font font, UI::Color color, int alpha) override {
      assert(x == (int)x);
      assert(y == (int)y);

      auto clip = _clipRectStack.back();
      x += clip.minX;
      y += clip.minY;

      if (y < clip.minY || y >= clip.maxY) {
        return;
      }

      auto instance = fontInstance(font);
      bool isMargin = color == UI::Color::FOREGROUND_MARGIN || color == UI::Color::FOREGROUND_MARGIN_HIGHLIGHTED;
      int attributes =
        isMargin ? COLOR_PAIR(SKY_COLOR_MARGIN) :
        color == UI::Color::FOREGROUND_KEYWORD || color == UI::Color::FOREGROUND_KEYWORD_CONSTANT ? COLOR_PAIR(SKY_COLOR_KEYWORD) :
        color == UI::Color::FOREGROUND_CONSTANT || color == UI::Color::FOREGROUND_NUMBER ? COLOR_PAIR(SKY_COLOR_CONSTANT) :
        color == UI::Color::FOREGROUND_COMMENT ? COLOR_PAIR(SKY_COLOR_COMMENT) :
        color == UI::Color::FOREGROUND_STRING ? COLOR_PAIR(SKY_COLOR_STRING) :
        color == UI::Color::FOREGROUND_DEFINITION ? A_BOLD :
        0;

      auto utf32 = codePointsFromString(text);
      int start = std::max(0, std::min(utf32->count(), clip.minX - (int)x));
      int end = std::max(0, std::min(utf32->count(), clip.maxX - (int)x));
      int n = std::max(0, end - start);
      cchar_t buffer;

      // Merge the characters with the background attributes already present
      for (int i = 0; i < n; i++) {
        mvin_wch(y, x + start, &buffer);
        int codePoint = (*utf32)[start + i];
        int advanceWidth = instance->advanceWidth(codePoint);

        // Non-printable characters (according to libc) will have an advance width of 0
        if (advanceWidth > 0) {
          // Transfer the text color
          int color = buffer.attr & A_COLOR;
          buffer.attr = PAIR_NUMBER(color) == 0 ? attributes : color | (attributes & A_BOLD);

          // Make sure rendering a space doesn't cover up the character underneath
          if (codePoint != ' ') {
            codePointToWchars(codePoint, buffer);
          }

          // Write over the contents at (x, y)
          mvadd_wch(y, x + start, &buffer);
          x += advanceWidth;
        }
      }
    }

    virtual void renderHorizontalLine(double x1, double x2, double y, UI::Color color) override {
    }

    virtual void renderVerticalLine(double x, double y1, double y2, UI::Color color) override {
    }

    virtual void renderScrollbarThumb(double x, double y, double width, double height, UI::Color color) override {
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        UI::Platform::__gc_mark();
        UI::Window::__gc_mark();
        UI::SemanticRenderer::__gc_mark();

        for (const auto &it : _fontInstances) {
          Skew::GC::mark(it.second);
        }
      }
    #endif

  private:
    void _writeToCommand(const char *command, const std::string &text) {
      if (FILE *f = popen(command, "w")) {
        fputs(text.c_str(), f);
        pclose(f);
      }
    }

    void _readFromCommand(const char *command) {
      if (FILE *f = popen(command, "r")) {
        char chunk[1024];
        std::string buffer;
        while (fgets(chunk, sizeof(chunk), f)) {
          buffer += chunk;
        }
        if (!pclose(f)) {
          _clipboard = std::move(buffer);
        }
      }
    }

    void _writeToClipboard(std::string text) {
      _writeToCommand("pbcopy", text);
      _writeToCommand("xclip -i -selection clipboard", text);
      _clipboard = std::move(text);
    }

    std::string _readFromClipboard() {
      _readFromCommand("pbpaste -Prefer text");
      _readFromCommand("xclip -o -selection clipboard");
      return _clipboard;
    }

    int _width = 0;
    int _height = 0;
    std::string _clipboard;
    std::vector<short> _buffer;
    std::vector<ClipRect> _clipRectStack;
    std::unordered_map<int, FontInstance *> _fontInstances;
  };
}

////////////////////////////////////////////////////////////////////////////////

static void handleEscapeSequence(Terminal::Host *host) {
  static std::unordered_map<std::string, Editor::Action> map = {
    { "[", Editor::Action::SELECT_FIRST_REGION },
    { "[3~", Editor::Action::DELETE_RIGHT_CHARACTER },
    { "[5~", Editor::Action::MOVE_UP_PAGE },
    { "[6~", Editor::Action::MOVE_DOWN_PAGE },
    { "[A", Editor::Action::MOVE_UP_LINE },
    { "[B", Editor::Action::MOVE_DOWN_LINE },
    { "[C", Editor::Action::MOVE_RIGHT_CHARACTER },
    { "[D", Editor::Action::MOVE_LEFT_CHARACTER },
    { "[F", Editor::Action::MOVE_RIGHT_LINE },
    { "[H", Editor::Action::MOVE_LEFT_LINE },
  };
  std::string sequence;

  // Escape sequences can have arbitrary length
  do {
    int c = getch();

    // If getch times out, this was just a plain escape
    if (c == -1) {
      break;
    }

    sequence += c;
  } while (sequence == "[" || sequence[sequence.size() - 1] < '@');

  // Dispatch an action if there's a match
  auto it = map.find(sequence);
  if (it != map.end()) {
    host->triggerAction(it->second);
  }
}

int main() {
  // Don't let errors from clipboard commands crap all over the editor UI
  fclose(stderr);

  // We want unicode support
  setlocale(LC_ALL, "en_US.UTF-8");

  // Let the ncurses library take over the screen and make sure it's cleaned up
  initscr();
  atexit([] { endwin(); });

  // Prepare colors
  start_color();
  use_default_colors();
  init_pair(SKY_COLOR_MARGIN, COLOR_BLUE, -1);
  init_pair(SKY_COLOR_KEYWORD, COLOR_RED, -1);
  init_pair(SKY_COLOR_COMMENT, COLOR_CYAN, -1);
  init_pair(SKY_COLOR_STRING, COLOR_GREEN, -1);
  init_pair(SKY_COLOR_CONSTANT, COLOR_MAGENTA, -1);
  init_pair(SKY_COLOR_SELECTED, COLOR_BLACK, COLOR_YELLOW);

  // More setup
  raw(); // Don't automatically generate any signals
  noecho(); // Don't auto-print typed characters
  curs_set(0); // Hide the cursor since we have our own carets
  timeout(10); // Don't let getch() block too long

  bool isInvalid = false;
  Skew::Root<Terminal::Host> host(new Terminal::Host);
  Skew::Root<Editor::App> app(new Editor::App(host.get()));
  Skew::Root<Editor::ShortcutMap> shortcuts(new Editor::ShortcutMap(host.get()));

  host->handleResize();
  host->render();

  while (true) {
    int c = getch();

    // Handle getch() timeout
    if (c == -1) {
      if (isInvalid) {
        host->render();
        isInvalid = false;
      } else {
        host->triggerFrame();
      }
      continue;
    }

    // Handle escape sequences
    if (c == 27) {
      handleEscapeSequence(host);
    }

    // Special-case the Control+Q shortcut to quit
    else if (c == 'Q' - 'A' + 1) {
      break;
    }

    // Handle shortcuts using control characters
    else if (c < 32 && c != '\n' && c != '\t') {
      auto action = shortcuts->get((UI::Key)((int)UI::Key::LETTER_A + c - 1), UI::Modifiers::CONTROL);
      if (action != Editor::Action::NONE) {
        host->triggerAction(action);
      }
    }

    // Special-case tab
    else if (c == '\t') {
      host->triggerAction(Editor::Action::INSERT_TAB_FORWARD);
    }

    // Special-case backspace
    else if (c == 127) {
      host->triggerAction(Editor::Action::DELETE_LEFT_CHARACTER);
    }

    // Handle regular typed text
    else if ((c >= 32 && c <= 0xFF) || c == '\n') {
      host->insertUTF8(c);
    }

    // Was the terminal resized?
    else if (c == KEY_RESIZE) {
      host->handleResize();
      resizeterm(host->size()->y, host->size()->x);
      host->render();
      continue;
    }

    // Only render after an idle delay in case there's a lot of input
    isInvalid = true;
  }

  return 0;
}
