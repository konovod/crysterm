require "../src/crysterm"

class MyProg
  include Crysterm

  d = Display.new
  s = Screen.new display: d, show_fps: false, dock_contrast: DockContrast::Blend

  style1 = Style.new fg: "black", bg: "#729fcf", border: Style.new(fg: "black", bg: "#729fcf"), scrollbar: Style.new(bg: "#000000"), track: Style.new(bg: "red")
  style2 = Style.new fg: "black", bg: "magenta", border: Style.new(fg: "black", bg: "#729fcf"), transparency: true
  # style2 = Style.new fg: "white", bg: "#870087", border: Style.new(fg: "black", bg: "#870087", transparency: true), transparency: true
  style3 = Style.new fg: "black", "bg": "#729fcf", border: Style.new(fg: "magenta", bg: "#729fcf"), bar: Style.new(fg: "#d75f00")

  chat = Widget::TextArea.new \
    top: 0,
    left: 0,
    width: "100%-19",
    height: "100%-2",
    content: "Chat session ...",
    parse_tags: false,
    border: true,
    style: style1,
    scrollbar: true

  input = Widget::TextBox.new \
    top: "100%-3",
    left: 0,
    width: "100%-19",
    height: 3,
    border: true,
    style: style1
  input.on(Crysterm::Event::Submit) do |e|
    chat.set_content "#{chat.content}\n#{e.value}"
    input.value = ""
    s.render
    input.focus
  end

  members = Widget::List.new \
    top: 0,
    left: "100%-20",
    width: 20,
    height: "100%-2",
    border: true,
    padding: 1,
    scrollbar: true,
    style: style2
  # padding: Padding.new( left: 1 ) # Triggers a visual bug? Possibly in combination with transparency?

  lag = Widget::ProgressBar.new \
    top: "100%-3",
    left: "100%-20",
    width: 20,
    height: 3,
    border: Border.new(type: BorderType::Line),
    content: "{center}Lag Indicator{/center}",
    parse_tags: true,
    filled: 10,
    style: style3

  s.append chat
  s.append members
  s.append lag
  s.append input

  input.focus

  # When q is pressed, exit the demo. All input first goes to the `Display`,
  # before being passed onto the focused widget, and then up its parent
  # tree. So attaching a handler to `Display` is the correct way to handle
  # the key press as early as possible.
  d.on(Event::KeyPress) do |e|
    case e.key
    when Tput::Key::CtrlQ
      exit
    when Tput::Key::Tab
      s.focus_next
    when Tput::Key::ShiftTab
      s.focus_previous
    end
  end

  spawn do
    id = 1
    loop do
      r = rand
      if r < 0.5
        members.append_item "Member #{id}"
        chat.set_content "#{chat.content}\n* Member #{id} has joined the conversation."
        id += 1
      else
        delid = rand(id) + 1
        members.items[delid]?.try do |item|
          members.remove_item(item) && \
             chat.set_content "#{chat.content}\n* #{item.content} has left."
        end
      end
      chat.scroll_to chat.get_content.lines.size
      # s.render
      sleep rand 2
      lag.filled = rand 100
      # s.render
    end
  end

  d.exec
end
