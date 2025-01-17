module Crysterm
  # Convenience namespace for widgets
  #
  #    include Widgets
  #    t = Text.new
  module Widgets
    # Blessed-like
    RadioButton    = Widget::RadioButton
    OverlayImage   = Widget::OverlayImage
    Input          = Widget::Input
    Checkbox       = Widget::Checkbox
    ProgressBar    = Widget::ProgressBar
    ScrollableBox  = Widget::ScrollableBox
    ScrollableText = Widget::ScrollableText
    Loading        = Widget::Loading
    Layout         = Widget::Layout
    Question       = Widget::Question
    TextBox        = Widget::TextBox
    TextArea       = Widget::TextArea
    Line           = Widget::Line
    ListTable      = Widget::ListTable
    List           = Widget::List
    Text           = Widget::Text
    BigText        = Widget::BigText
    RadioSet       = Widget::RadioSet
    Button         = Widget::Button
    Prompt         = Widget::Prompt
    Box            = Widget::Box
    Message        = Widget::Message
    LogLine        = Widget::LogLine

    # Qt-like
    Menu = Widget::Menu

    # Pine-like
    PineHeaderBar = Widget::Pine::HeaderBar
    PineStatusBar = Widget::Pine::StatusBar
  end
end
