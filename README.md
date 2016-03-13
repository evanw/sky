# Sky Text Editor

A text editor written in the Skew programming language.
It uses a custom GPU-powered text editing component to render text at 60fps and implements selection, high-DPI rendering, scrollbars, keyboard shortcuts, clipboard support, syntax highlighting, tab stops, variable-width unicode characters, IME text entry, and multiple cursors.
It currently targets OS X using cross-compiled C++ with OpenGL, the web using cross-compiled JavaScript with WebGL, and the terminal using cross-compiled C++ with ncurses.
The web build also has a 2D canvas fallback if WebGL isn't supported so text rendering works as far back as Firefox 3.6.
Because it's written in Skew, the generated JavaScript is extremely compact (under 50kb at the time of writing).
This is a toy project and is not intended for real use.

[Live demo](http://evanw.github.io/sky/)
