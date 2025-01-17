require "./box"

module Crysterm
  class Widget
    # Question element
    class Question < Box
      property text : String = ""

      @visible = false

      # TODO Positioning is bad for buttons.
      # Use a layout for buttons.
      # Also, make unlimited number of buttons/choices possible.

      @ok = Button.new(
        left: 1,
        top: 4,
        width: 6,
        height: 1,
        resizable: true,
        content: "Okay",
        align: Tput::AlignFlag::Center,
        # bg: "black",
        # hover_bg: "blue",
        focus_on_click: false,
              # mouse: true
)

      @cancel = Button.new(
        left: 8,
        top: 4,
        width: 8,
        height: 1,
        resizable: true,
        content: "Cancel",
        align: Tput::AlignFlag::Center,
        # bg: "black",
        # hover_bg: "blue",
        focus_on_click: false,
              # mouse: true
)

      def initialize(**box)
        box["content"]?.try do |c|
          @text = c
        end

        super **box

        # Should not be needed when ivar exists and is already set
        # @visible = box["visible"]? ? true : box["hidden"]? || false

        append @ok
        append @cancel
      end

      def ask(text = nil, &block : String?, Bool -> Nil)
        # D O:
        # Keep above:
        # @parent.try do |p|
        #   detach
        #   p.append self
        # end

        set_content text || @text
        show

        done = uninitialized String?, Bool -> Nil

        ev_keys = screen.on(Crysterm::Event::KeyPress) do |e|
          # if (e.key == 'mouse')
          #  return
          # end
          c = e.char
          k = e.key

          if (k != Tput::Key::Enter && k != Tput::Key::Escape && c != 'q' && c != 'y' && c != 'n')
            next
          end

          done.call nil, k == Tput::Key::Enter || e.char == 'y'
        end

        ev_ok = @ok.on(Crysterm::Event::Press) do
          done.call nil, true
        end

        ev_cancel = @cancel.on(Crysterm::Event::Press) do
          done.call nil, false
        end

        screen.save_focus
        focus

        done = ->(err : String?, data : Bool) do
          hide
          screen.restore_focus
          screen.off Crysterm::Event::KeyPress, ev_keys
          @ok.off Crysterm::Event::Press, ev_ok
          @cancel.off Crysterm::Event::Press, ev_cancel
          block.call err, data
          screen.render
        end

        screen.render
      end
    end
  end
end
