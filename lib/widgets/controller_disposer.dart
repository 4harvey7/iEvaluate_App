// Disposes the controllers of a bottom sheet or dialog at the right moment.
//
// The Future returned by showModalBottomSheet / showDialog completes the
// instant the route is popped -- BEFORE its exit animation plays. Disposing
// TextEditingControllers in `.whenComplete()` therefore kills them while the
// TextFields are still on screen. Any rebuild during the slide-out (focus
// loss, keyboard closing) re-subscribes to the dead controller and throws
// "A TextEditingController was used after being disposed", which corrupts the
// widget tree so the NEXT edit crashes the screen.
//
// Wrap the sheet/dialog content in this widget instead. Its State is only
// disposed when the route's subtree is really unmounted, i.e. after the exit
// animation, and after the TextFields themselves have let go.

import 'package:flutter/widgets.dart';

class ControllerDisposer extends StatefulWidget {
  const ControllerDisposer({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<ControllerDisposer> createState() => _ControllerDisposerState();
}

class _ControllerDisposerState extends State<ControllerDisposer> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
