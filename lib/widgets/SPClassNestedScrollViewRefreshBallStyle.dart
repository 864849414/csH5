// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:changshengh5/pages/common/AnimationImagePage.dart';
import 'package:changshengh5/utils/SPClassCommonMethods.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';



// The over-scroll distance that moves the indicator to its maximum
// displacement, as a percentage of the scrollable's container extent.
const double _kDragContainerExtentPercentage = 0.25;

// How much the scroll's drag gesture can overshoot the RefreshIndicator's
// displacement; max displacement = _kDragSizeFactorLimit * displacement.
const double _kDragSizeFactorLimit = 1.5;

// When the scroll ends, the duration of the refresh indicator's animation
// to the RefreshIndicator's displacement.
const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);

// The duration of the ScaleTransition that starts when the refresh action
// has completed.
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);

/// The signature for a function that's called when the user has dragged a
/// [SPClassNestedScrollViewRefreshBallStyle] far enough to demonstrate that they want the app to
/// refresh. The returned [Future] must complete when the refresh operation is
/// finished.
///
/// Used by [SPClassNestedScrollViewRefreshBallStyle.onRefresh].
typedef NestedScrollViewRefreshCallback = Future<void> Function();

// The state machine moves through these modes only when the scrollable
// identified by scrollableKey has been scrolled to its min or max limit.
enum _RefreshIndicatorMode {
  drag, // Pointer is down.
  armed, // Dragged far enough that an up event will run the onRefresh callback.
  snap, // Animating to the indicator's final "displacement".
  refresh, // Running the refresh callback.
  done, // Animating the indicator's fade-out after refreshing.
  canceled, // Animating the indicator's fade-out after not arming.
}

/// A widget that supports the Material "swipe to refresh" idiom.
///
/// When the child's [Scrollable] descendant overscrolls, an animated circular
/// progress indicator is faded into view. When the scroll ends, if the
/// indicator has been dragged far enough for it to become completely opaque,
/// the [onRefresh] callback is called. The callback is expected to update the
/// scrollable's contents and then complete the [Future] it returns. The refresh
/// indicator disappears after the callback's [Future] has completed.
///
/// If the [Scrollable] might not have enough content to overscroll, consider
/// settings its `physics` property to [AlwaysScrollableScrollPhysics]:
///
/// ```dart
/// ListView(
///   physics: const AlwaysScrollableScrollPhysics(),
///   children: ...
//  )
/// ```
///
/// Using [AlwaysScrollableScrollPhysics] will ensure that the scroll view is
/// always scrollable and, therefore, can trigger the [SPClassNestedScrollViewRefreshBallStyle].
///
/// A [SPClassNestedScrollViewRefreshBallStyle] can only be used with a vertical scroll view.
///
/// See also:
///
///  * <https://material.google.com/patterns/swipe-to-refresh.html>
///  * [SPClassNestedScrollViewRefreshBallStyleState], can be used to programmatically show the refresh indicator.
///  * [RefreshProgressIndicator], widget used by [SPClassNestedScrollViewRefreshBallStyle] to show
///    the inner circular progress spinner during refreshes.
///  * [CupertinoSliverRefreshControl], an iOS equivalent of the pull-to-refresh pattern.
///    Must be used as a sliver inside a [CustomScrollView] instead of wrapping
///    around a [ScrollView] because it's a part of the scrollable instead of
///    being overlaid on top of it.
class SPClassNestedScrollViewRefreshBallStyle extends StatefulWidget {
  /// Creates a refresh indicator.
  ///
  /// The [onRefresh], [child], and [notificationPredicate] arguments must be
  /// non-null. The default
  /// [displacement] is 40.0 logical pixels.
  const SPClassNestedScrollViewRefreshBallStyle({
    Key ?key,
    required this.child,
    required this.onRefresh,
    this.textColor,
    this.backgroundColor,
    this.notificationPredicate = nestedScrollViewScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
  })  : assert(child != null),
        assert(onRefresh != null),
        assert(notificationPredicate != null),
        super(key: key);

  /// The widget below this widget in the tree.
  ///
  /// The refresh indicator will be stacked on top of this child. The indicator
  /// will appear when child's Scrollable descendant is over-scrolled.
  ///
  /// Typically a [ListView] or [CustomScrollView].
  final Widget child;
  final Color ?textColor ;
  /// The distance from the child's top or bottom edge to where the refresh
  /// indicator will settle. During the drag that exposes the refresh indicator,
  /// its actual displacement may significantly exceed this value.

  /// A function that's called when the user has dragged the refresh indicator
  /// far enough to demonstrate that they want the app to refresh. The returned
  /// [Future] must complete when the refresh operation is finished.
  final NestedScrollViewRefreshCallback onRefresh;


  /// The progress indicator's background color. The current theme's
  /// [ThemeData.canvasColor] by default.
  final Color ?backgroundColor;

  /// A check that specifies whether a [ScrollNotification] should be
  /// handled by this widget.
  ///
  /// By default, checks whether `notification.depth == 0`. Set it to something
  /// else for more complicated layouts.
  final ScrollNotificationPredicate notificationPredicate;

  /// {@macro flutter.material.progressIndicator.semanticsLabel}
  ///
  /// This will be defaulted to [MaterialLocalizations.refreshIndicatorSemanticLabel]
  /// if it is null.
  final String ?semanticsLabel;

  /// {@macro flutter.material.progressIndicator.semanticsValue}
  final String ?semanticsValue;
  @override
  SPClassNestedScrollViewRefreshBallStyleState createState() =>
      SPClassNestedScrollViewRefreshBallStyleState();
}

/// Contains the state for a [SPClassNestedScrollViewRefreshBallStyle]. This class can be used to
/// programmatically show the refresh indicator, see the [show] method.
class SPClassNestedScrollViewRefreshBallStyleState
    extends State<SPClassNestedScrollViewRefreshBallStyle>
    with TickerProviderStateMixin<SPClassNestedScrollViewRefreshBallStyle> {
  AnimationController ?_positionController;
  Animation<double> ?_positionFactor;

  Animation<Color?> ?_valueColor;
  AnimationController ?spProControllerLoading;

  _RefreshIndicatorMode ?_mode;
  Future<void> ?_pendingRefreshFuture;
  bool ?_isIndicatorAtTop;
  double ?_dragOffset;


  static final Animatable<double> _kDragSizeFactorLimitTween =
  Tween<double>(begin: 0.0, end: _kDragSizeFactorLimit);

// 更新时间
  DateTime ?_dateTime;
  /// 更多信息
  final String spProInfoText="最后更新时间 %T";
  // 获取更多信息
  String get _infoText {
    if (_mode== _RefreshIndicatorMode.refresh) {
      _dateTime = DateTime.now();
    }
    String fillChar = _dateTime!.minute < 10 ? "0" : "";
    return  spProInfoText
        .replaceAll("%T", "${_dateTime!.hour}:$fillChar${_dateTime!.minute}");
  }
  @override
  void initState() {
    super.initState();

    _dateTime=DateTime.now();
    _positionController = AnimationController(vsync: this);
    _positionFactor = _positionController!.drive(_kDragSizeFactorLimitTween);

    spProControllerLoading= AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    spProControllerLoading!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        //动画从 controller.forward() 正向执行 结束时会回调此方法
        //重置起点
        spProControllerLoading!.reset();
        //开启
        spProControllerLoading!.forward();
      }
    });
    spProControllerLoading!.forward();

  }

  @override
  void didChangeDependencies() {
    final ThemeData theme = Theme.of(context);
    _valueColor = _positionController!.drive(
      ColorTween(
          begin: (theme.accentColor).withOpacity(0.0),
          end: (theme.accentColor).withOpacity(1.0))
          .chain(CurveTween(
          curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit))),
    );
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    if(spProControllerLoading!=null){
      spProControllerLoading!.dispose();
    }
    _positionController!.dispose();
    super.dispose();
  }

  double maxContainerExtent = 0.0;
  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;
    maxContainerExtent = math.max(
        notification.metrics.viewportDimension, this.maxContainerExtent);
    if (notification is ScrollStartNotification &&
        notification.metrics.extentBefore == 0.0 &&
        _mode == null &&
        _start(notification.metrics.axisDirection)) {
      setState(() {
        _mode = _RefreshIndicatorMode.drag;
      });
      return false;
    }
    bool? indicatorAtTopNow;
    switch (notification.metrics.axisDirection) {
      case AxisDirection.down:
        indicatorAtTopNow = true;
        break;
      case AxisDirection.up:
        indicatorAtTopNow = false;
        break;
      case AxisDirection.left:
      case AxisDirection.right:
        indicatorAtTopNow = null;
        break;
    }
    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_mode == _RefreshIndicatorMode.drag ||
          _mode == _RefreshIndicatorMode.armed)
        _dismiss(_RefreshIndicatorMode.canceled);
    } else if (notification is ScrollUpdateNotification) {
      if (_mode == _RefreshIndicatorMode.drag ||
          _mode == _RefreshIndicatorMode.armed) {
        if (notification.metrics.extentBefore > 0.0) {
          _dismiss(_RefreshIndicatorMode.canceled);
        } else {
          _dragOffset = _dragOffset!-notification.scrollDelta!;
          _checkDragOffset(maxContainerExtent);
        }
      }
      if (_mode == _RefreshIndicatorMode.armed &&
          notification.dragDetails == null) {
        // On iOS start the refresh when the Scrollable bounces back from the
        // overscroll (ScrollNotification indicating this don't have dragDetails
        // because the scroll activity is not directly triggered by a drag).
        _show();
      }
    } else if (notification is OverscrollNotification) {
      if (_mode == _RefreshIndicatorMode.drag ||
          _mode == _RefreshIndicatorMode.armed) {
        _dragOffset = _dragOffset!- notification.overscroll / 2.0;
        _checkDragOffset(maxContainerExtent);

      }
    } else if (notification is ScrollEndNotification) {
      switch (_mode) {
        case _RefreshIndicatorMode.armed:
          _show();
          break;
        case _RefreshIndicatorMode.drag:
          _dismiss(_RefreshIndicatorMode.canceled);
          break;
        default:
        // do nothing
          break;
      }
    }
    return false;
  }

  bool _handleGlowNotification(OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) return false;
    if (_mode == _RefreshIndicatorMode.drag) {
      notification.disallowGlow();
      return true;
    }
    return false;
  }

  bool _start(AxisDirection direction) {
    assert(_mode == null);
    assert(_isIndicatorAtTop == null);
    assert(_dragOffset == null);
    switch (direction) {
      case AxisDirection.down:
        _isIndicatorAtTop = true;
        break;
      case AxisDirection.up:
        _isIndicatorAtTop = false;
        break;
      case AxisDirection.left:
      case AxisDirection.right:
        _isIndicatorAtTop = null;
        // we do not support horizontal scroll views.
        return false;
    }
    _dragOffset = 0.0;
    _positionController!.value = 0.0;
    return true;
  }

  void _checkDragOffset(double containerExtent) {
    assert(_mode == _RefreshIndicatorMode.drag ||
        _mode == _RefreshIndicatorMode.armed);
    double newValue =
        _dragOffset! / (containerExtent * _kDragContainerExtentPercentage);
    if (_mode == _RefreshIndicatorMode.armed)
      newValue = math.max(newValue, 1.0 / _kDragSizeFactorLimit);
    _positionController!.value =
        newValue.clamp(0.0, 1.0); // this triggers various rebuilds
    if (_mode == _RefreshIndicatorMode.drag && _valueColor!.value!.alpha == 0xFF)
      _mode = _RefreshIndicatorMode.armed;
  }

  // Stop showing the refresh indicator.
  Future<void> _dismiss(_RefreshIndicatorMode newMode) async {
    await Future<void>.value();
    // This can only be called from _show() when refreshing and
    // _handleScrollNotification in response to a ScrollEndNotification or
    // direction change.
    assert(newMode == _RefreshIndicatorMode.canceled ||
        newMode == _RefreshIndicatorMode.done);
    setState(() {
      _mode = newMode;
    });
    switch (_mode) {
      case _RefreshIndicatorMode.done:
        await _positionController!.animateTo(0.0,
            duration: _kIndicatorScaleDuration);
        break;
      case _RefreshIndicatorMode.canceled:
        await _positionController!.animateTo(0.0,
            duration: _kIndicatorScaleDuration);
        break;
      default:
        assert(false);
    }
    if (mounted && _mode == newMode) {
      _dragOffset = null;
      _isIndicatorAtTop = null;
      setState(() {
        _mode = null;
      });
    }
  }

  void _show() {
    assert(_mode != _RefreshIndicatorMode.refresh);
    assert(_mode != _RefreshIndicatorMode.snap);
    final Completer<void> completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _mode = _RefreshIndicatorMode.snap;
    _positionController!
        .animateTo(1.0 / _kDragSizeFactorLimit,
        duration: _kIndicatorSnapDuration)
        .then<void>((void value) {
      if (mounted && _mode == _RefreshIndicatorMode.snap) {
        assert(widget.onRefresh != null);
        setState(() {
          // Show the indeterminate progress indicator.
          _mode = _RefreshIndicatorMode.refresh;
        });
        final Future<void> refreshResult = widget.onRefresh();
        assert(() {
          if (refreshResult == null)
            FlutterError.reportError(FlutterErrorDetails(
              exception: FlutterError('The onRefresh callback returned null.\n'
                  'The RefreshIndicator onRefresh callback must return a Future.'),
              context: ErrorDescription('when calling onRefresh'),
              library: 'material library',
            ));
          return true;
        }());
        if (refreshResult == null) return;
        refreshResult.whenComplete(() {
          if (mounted && _mode == _RefreshIndicatorMode.refresh) {
            completer.complete();
            _dismiss(_RefreshIndicatorMode.done);
          }
        });
      }
    });
  }

  /// Show the refresh indicator and run the refresh callback as if it had
  /// been started interactively. If this method is called while the refresh
  /// callback is running, it quietly does nothing.
  ///
  /// Creating the [SPClassNestedScrollViewRefreshBallStyle] with a [GlobalKey<RefreshIndicatorState>]
  /// makes it possible to refer to the [SPClassNestedScrollViewRefreshBallStyleState].
  ///
  /// The future returned from this method completes when the
  /// [SPClassNestedScrollViewRefreshBallStyle.onRefresh] callback's future completes.
  ///
  /// If you await the future returned by this function from a [State], you
  /// should check that the state is still [mounted] before calling [setState].
  ///
  /// When initiated in this manner, the refresh indicator is independent of any
  /// actual scroll view. It defaults to showing the indicator at the top. To
  /// show it at the bottom, set `atTop` to false.
  Future<void>? show({bool atTop = true}) {
    if (_mode != _RefreshIndicatorMode.refresh &&
        _mode != _RefreshIndicatorMode.snap) {
      if (_mode == null) _start(atTop ? AxisDirection.down : AxisDirection.up);
      _show();
    }
    return _pendingRefreshFuture;
  }

  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    final Widget child = NotificationListener<ScrollNotification>(
      key: _key,
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleGlowNotification,
        child: widget.child,
      ),
    );
    if (_mode == null) {
      assert(_dragOffset == null);
      assert(_isIndicatorAtTop == null);
      return child;
    }
    assert(_dragOffset != null);
    assert(_isIndicatorAtTop != null);

    final bool showIndeterminateIndicator =
        _mode == _RefreshIndicatorMode.refresh ||
            _mode == _RefreshIndicatorMode.done;

    return Column(
      children: <Widget>[
        SizeTransition(
          axisAlignment: _isIndicatorAtTop! ? 1.0 : -1.0,
          sizeFactor: _positionFactor!, // this is what brings it down
          child:  Container(
            color: Color(0xFFF1F1F1),
            padding: EdgeInsets.only(top: height(12),bottom: height(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(
                    right: 10.0,
                  ),
                  child: (_mode== _RefreshIndicatorMode.refresh )
                      ?
                  AnimationImagePage(width: width(50),height: width(50),)
                      :Image.asset(
                    'assets/animationImages/足球动效_00007.png',
                    width: width(50),
                    height: width(50),
                  )
                  // RotationTransition(
                  //   turns: spProControllerLoading,
                  //   alignment: Alignment.center,
                  //   child:SPClassEncryptImage.asset(
                  //     SPClassImageUtil.spFunGetImagePath('ic_ball_loadding'),
                  //     width:  height(24),
                  //   ) ,
                  // ):SPClassEncryptImage.asset(
                  //   SPClassImageUtil.spFunGetImagePath("ic_ball_loadding"),
                  //   width: height(24),
                  // ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      "${getRefreshText()}",
                      style: TextStyle(
                        fontSize: sp(10),
                        color: widget.textColor,
                      ),
                    ),
                     Container(
                      margin: EdgeInsets.only(
                        top: 2.0,
                      ),
                      child: Text(
                        _infoText,
                        style: TextStyle(
                          fontSize: sp(10),
                          color: widget.textColor,
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
        Expanded(
          child: child,
        )

      ],
    );
  }

  getRefreshText() {
     switch(_mode){

       case _RefreshIndicatorMode.drag:
         return "下拉刷新";
         // TODO: Handle this case.
         break;
       case _RefreshIndicatorMode.armed:
         return "下拉刷新2";
         // TODO: Handle this case.
         break;
       case _RefreshIndicatorMode.snap:
         return "下拉刷新3";

         // TODO: Handle this case.
         break;
       case _RefreshIndicatorMode.refresh:
         return "刷新中...";
         // TODO: Handle this case.
         break;
       case _RefreshIndicatorMode.done:
         return "刷新完成";
         // TODO: Handle this case.
         break;
       case _RefreshIndicatorMode.canceled:
          return "刷新完成";
         // TODO: Handle this case.
         break;
     }

     return "";
  }
}

//return true so that we can handle inner scroll notification
bool nestedScrollViewScrollNotificationPredicate(
    ScrollNotification notification) {
  return true;
}
