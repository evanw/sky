#define SKEW_GC_MARK_AND_SWEEP
#import <skew.h>

namespace Log {
  void info(const Skew::string &text) {}
  void warning(const Skew::string &text) {}
  void error(const Skew::string &text) {}
}

#import "compiled.cpp"
#import <skew.cpp>
#import <ncurses.h>
#import <codecvt>
#import <locale>

////////////////////////////////////////////////////////////////////////////////

enum {
  SKY_COLOR_COMMENT = 1,
  SKY_COLOR_CONSTANT = 2,
  SKY_COLOR_KEYWORD = 3,
  SKY_COLOR_MARGIN = 4,
  SKY_COLOR_SELECTED = 5,
  SKY_COLOR_STRING = 6,
};

namespace Terminal {
  struct Host : Editor::Platform, private Editor::Window, private Editor::SemanticRenderer {
    void showCarets() {
      _areCaretsVisible = true;
    }

    void toggleCarets() {
      _areCaretsVisible = !_areCaretsVisible;
    }

    void handleResize() {
      _width = getmaxx(stdscr);
      _height = getmaxy(stdscr);
      _view->resize(_width - 1, _height); // Subtract 1 so the cursor can be seen at the end of the line
    }

    void render() {
      clear();
      _view->render();
      refresh();
    }

    void triggerAction(Editor::Action action) {
      if (action == Editor::Action::CUT || action == Editor::Action::COPY) {
        auto selection = _view->selection()->isEmpty() ? _view->selectionExpandedToLines() : _view->selection();
        _clipboard = _view->textInSelection(selection).std_str();

        if (action == Editor::Action::CUT) {
          _view->changeSelection(selection, Editor::ScrollBehavior::DO_NOT_SCROLL);
          _view->insertText("");
        }
      }

      else if (action == Editor::Action::PASTE) {
        _view->insertText(_clipboard);
      }

      else {
        _view->triggerAction(action);
      }
    }

    void insertASCII(char c) {
      _view->insertText(std::string(1, c));
    }

    virtual Editor::OperatingSystem operatingSystem() override {
      return Editor::OperatingSystem::UNKNOWN;
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
      return nullptr;
    }

    virtual Editor::Window *createWindow() override {
      return this;
    }

    virtual Editor::SemanticRenderer *renderer() override {
      return this;
    }

    virtual void setView(Editor::View *view) override {
      _view = view;
      _view->resizeFont(1, 1, 1);
      _view->setScrollbarThickness(1);
      _view->changePadding(0, 0, 0, 0);
      _view->changeMarginPadding(1, 1);
      _view->triggerAction(Editor::Action::SELECT_ALL);
      _view->insertText(
        "Shortcuts:\n"
        "\n"
        "Ctrl+Q: Quit\n"
        "Ctrl+X: Cut\n"
        "Ctrl+C: Copy\n"
        "Ctrl+V: Paste\n"
        "Ctrl+A: Select All\n"
        "Ctrl+Z: Undo\n"
        "Ctrl+Y: Redo\n");
      _view->triggerAction(Editor::Action::MOVE_UP_DOCUMENT);
      handleResize();
    }

    virtual void setTitle(Skew::string title) override {
    }

    virtual void invalidate() override {
    }

    virtual void setCursor(Editor::Cursor cursor) override {
    }

    virtual void renderRect(double x, double y, double width, double height, Editor::Color color) override {
      if (color == Editor::Color::BACKGROUND_SELECTED) {
        int minX = std::max((int)x, (int)_view->marginWidth());
        int minY = std::max((int)y, 0);
        int maxX = std::min((int)(x + width), _width);
        int maxY = std::min((int)(y + height), _height);
        int n = std::max(0, maxX - minX);
        chtype buffer[n];

        for (int y = minY; y < maxY; y++) {
          mvinchnstr(y, minX, buffer, n);
          for (int x = 0; x < n; x++) {
            buffer[x] = (buffer[x] & ~A_COLOR) | COLOR_PAIR(SKY_COLOR_SELECTED);
          }
          mvaddchnstr(y, minX, buffer, n);
        }
      }
    }

    virtual void renderCaret(double x, double y, Editor::Color color) override {
      assert(x == (int)x);
      assert(y == (int)y);

      if (!_areCaretsVisible || x < 0 || y < 0 || x >= _width || y >= _height) {
        return;
      }

      mvaddch(y, x, mvinch(y, x) | A_UNDERLINE);
    }

    virtual void renderSquiggle(double x, double y, double width, double height, Editor::Color color) override {
    }

    virtual void renderRightwardShadow(double x, double y, double width, double height) override {
    }

    virtual void renderText(double x, double y, Skew::string text, Editor::Font font, Editor::Color color, int alpha) override {
      assert(x == (int)x);
      assert(y == (int)y);

      if (y < 0 || y >= _height) {
        return;
      }

      bool isMargin = color == Editor::Color::FOREGROUND_MARGIN || color == Editor::Color::FOREGROUND_MARGIN_HIGHLIGHTED;
      int attributes =
        isMargin ? COLOR_PAIR(SKY_COLOR_MARGIN) :
        color == Editor::Color::FOREGROUND_KEYWORD || color == Editor::Color::FOREGROUND_KEYWORD_CONSTANT ? COLOR_PAIR(SKY_COLOR_KEYWORD) :
        color == Editor::Color::FOREGROUND_CONSTANT || color == Editor::Color::FOREGROUND_NUMBER ? COLOR_PAIR(SKY_COLOR_CONSTANT) :
        color == Editor::Color::FOREGROUND_COMMENT ? COLOR_PAIR(SKY_COLOR_COMMENT) :
        color == Editor::Color::FOREGROUND_STRING ? COLOR_PAIR(SKY_COLOR_STRING) :
        color == Editor::Color::FOREGROUND_DEFINITION ? A_BOLD :
        0;

      auto utf32 = std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t>().from_bytes(text.std_str());
      int minX = isMargin ? 0 : _view->marginWidth();
      int maxX = _width - 1; // Subtract 1 so the cursor can be seen at the end of the line
      int start = std::max(0, std::min((int)utf32.size(), minX - (int)x));
      int end = std::max(0, std::min((int)utf32.size(), maxX - (int)x));
      int n = std::max(0, end - start);
      chtype buffer[n];

      mvinchnstr(y, x + start, buffer, n);
      for (int i = 0; i < n; i++) {
        int color = buffer[i] & A_COLOR;
        int c = utf32[start + i];
        if (c == ' ') c = buffer[i] & (~A_ATTRIBUTES | A_ALTCHARSET);
        else if (c == 0xB7) c = 126 | A_ALTCHARSET;
        else if (c > 0xFF) c = '?';
        buffer[i] = (PAIR_NUMBER(color) == 0 ? attributes : color | (attributes & A_BOLD)) | c;
      }
      mvaddchnstr(y, x + start, buffer, n);
    }

    virtual void renderHorizontalLine(double x1, double x2, double y, Editor::Color color) override {
    }

    virtual void renderVerticalLine(double x, double y1, double y2, Editor::Color color) override {
    }

    virtual void renderScrollbarThumb(double x, double y, double width, double height, Editor::Color color) override {
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
        Skew::GC::mark(_view);
      }
    #endif

  private:
    int _width = 0;
    int _height = 0;
    bool _areCaretsVisible = true;
    std::string _clipboard;
    std::vector<short> _buffer;
    Editor::View *_view = nullptr;
  };
}

////////////////////////////////////////////////////////////////////////////////

static void handleEscapeSequence(Terminal::Host *host) {
  static std::unordered_map<std::string, Editor::Action> map = {
    { "[", Editor::Action::SELECT_FIRST_REGION },
    { "[3~", Editor::Action::DELETE_RIGHT_CHARACTER },
    { "[A", Editor::Action::MOVE_UP_LINE },
    { "[B", Editor::Action::MOVE_DOWN_LINE },
    { "[C", Editor::Action::MOVE_RIGHT_CHARACTER },
    { "[D", Editor::Action::MOVE_LEFT_CHARACTER },
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

static void handleControlCharacter(Terminal::Host *host, char c) {
  static std::unordered_map<char, Editor::Action> map = {
    { 'A', Editor::Action::SELECT_ALL },
    { 'C', Editor::Action::COPY },
    { 'V', Editor::Action::PASTE },
    { 'X', Editor::Action::CUT },
    { 'Y', Editor::Action::REDO },
    { 'Z', Editor::Action::UNDO },
  };

  auto it = map.find(c);
  if (it != map.end()) {
    host->triggerAction(it->second);
  }
}

int main() {
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
  timeout(50); // Don't let getch() block too long, need to blink the carets

  int blinkToggle = 0;
  auto host = new Terminal::Host;
  Skew::Root<Editor::App> app(new Editor::App(host));

  host->render();

  while (true) {
    int c = getch();

    // Handle getch() timeout for blinking carets
    if (c == -1) {
      if (++blinkToggle == 10) {
        host->toggleCarets();
        blinkToggle = 0;
      } else {
        continue;
      }
    }

    // Reset blinking any time anything happens
    else {
      host->showCarets();
      blinkToggle = 0;
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
      handleControlCharacter(host, c + 'A' - 1);
    }

    // Special-case backspace
    else if (c == 127) {
      host->triggerAction(Editor::Action::DELETE_LEFT_CHARACTER);
    }

    // Handle regular typed text
    else if ((c >= 32 && c < 127) || c == '\n') {
      host->insertASCII(c);
    }

    host->render();
    Skew::GC::collect();
  }

  return 0;
}
