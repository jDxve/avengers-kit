import 'package:flutter/material.dart'; // allowed
import 'package:fixture/common/resources/strings.dart'; // allowed
import 'package:fixture/common/widgets/button.dart'; // allowed
import 'package:fixture/features/orders/domain/models/order.dart'; // allowed
import 'package:fixture/features/billing/domain/models/invoice.dart'; // allowed
import 'package:fixture/features/orders/presentation/ui/order_card.dart'; // allowed
import 'order_card.dart'; // allowed: relative form
import 'dart:ui'; // allowed
// expect: ui_purity
import 'package:flutter_riverpod/flutter_riverpod.dart';
// expect: ui_purity
import 'package:dio/dio.dart';
// expect: ui_purity
import 'dart:io';
// expect: ui_purity
import 'package:fixture/features/orders/presentation/notifier/orders_notifier.dart';
// expect: ui_purity
import '../notifier/orders_notifier.dart';
// expect: ui_purity
import 'package:fixture/features/orders/domain/repository/orders_repository.dart';
// expect: ui_purity
import 'package:fixture/features/orders/orders.dart';
// expect: ui_purity
import 'package:fixture/core/state/data_state.dart';
// expect: ui_purity
import 'package:fixture/common/notifiers/toast.dart';
