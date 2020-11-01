#!/usr/bin/env python3

# Usage:
# ./scrollfrequency.py | tee -a /tmp/rtlclient.control.txt | cat > /dev/null

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

class MyWindow(Gtk.Window):

    def __init__(self):
        Gtk.Window.__init__(self, title="Hello World")

        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        # adjustments (initial value, min value, max value,
        # step increment - press cursor keys to see!,
        # page increment - click around the handle to see!,
        # page size - not used here)
        #ad1 = Gtk.Adjustment(0, 0, 100, 5, 10, 0) 
        freq_adj = Gtk.Adjustment(value=400000000, lower=400000000, upper=406000000, step_increment=10000, page_increment=500000, page_size=0) 
        gain_adj = Gtk.Adjustment(value=0, lower=0, upper=50, step_increment=1, page_increment=10, page_size=0) 
#        ad1 = Gtk.Adjustment(430000000, 430000000, 436000000, 10000, 1000000, 0) 

        # an horizontal scale
        self.freq_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=freq_adj);
        # of integers (no digits)
        self.freq_scale.set_digits(0)
        # that can expand horizontally if there is space in the grid (see below)
        self.freq_scale.set_hexpand(True)
        # that is aligned at the top of the space allowed in the grid (see below)
        self.freq_scale.set_valign(Gtk.Align.START) 

        # we connect the signal "value-changed" emitted by the scale with the callback
        # function scale_moved
        self.freq_scale.connect("value-changed", self.freq_scale_moved)
        self.box.pack_start(self.freq_scale, True, True, 0)

        self.gain_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=gain_adj);
        self.gain_scale.set_digits(0)
        self.gain_scale.set_hexpand(True)
        self.gain_scale.set_valign(Gtk.Align.START) 

        self.gain_scale.connect("value-changed", self.gain_scale_moved)
        self.box.pack_start(self.gain_scale, True, True, 0)

        self.button = Gtk.Button(label="Exit")
        self.add(self.box)
        self.button.connect("clicked", Gtk.main_quit)
        self.box.pack_start(self.button, True, True, 0)




    # any signal from the scales is signaled to the label the text of which is
    # changed
    def freq_scale_moved(self, event):
        print("freq ", str(int(self.freq_scale.get_value())), flush=True)

    def gain_scale_moved(self, event):
        print("gain ", str(10*int(self.gain_scale.get_value())), flush=True)


win = MyWindow()
win.connect("destroy", Gtk.main_quit)
win.show_all()
Gtk.main()

