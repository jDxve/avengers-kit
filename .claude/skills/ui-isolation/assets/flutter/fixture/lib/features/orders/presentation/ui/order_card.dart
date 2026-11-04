class StatelessWidget {}
class StatefulWidget {}
class OrderCard extends StatelessWidget {} // allowed
class HookWidget {}
// expect: ui_stateless
class OrderTicker extends StatefulWidget {}
// expect: ui_stateless
class OrderCounter extends HookWidget {}
// ADR-010: visual state only, an animation controller.
// ignore: app_lints/ui_stateless
class OrderPulse extends StatefulWidget {}
