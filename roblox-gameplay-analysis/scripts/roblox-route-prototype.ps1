param(
    [string]$RouteJson, [switch]$DryRun, [switch]$SelfTest, [switch]$CaptureProbe, [switch]$TraceReturn,
    [int]$ReferenceWidth, [int]$ReferenceHeight, [int]$ReturnTurnX = 600
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

public static class RobloxRouteNative {
    private static int referenceWidth, referenceHeight;
    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct ClientRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Keyboard { public ushort VirtualKey, ScanCode; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit, Size = 32)]
    private struct InputData { [FieldOffset(0)] public Keyboard Keyboard; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputData Data; }

    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out ClientRect bounds);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint MapVirtualKey(uint code, uint mode);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, int x, int y, int data, UIntPtr extra);

    // Interpret route coordinates at the resolution used to calibrate the route.
    public static void UseReferenceSize(int width, int height) {
        if (width <= 0 || height <= 0) throw new ArgumentException("Both reference dimensions must be positive.");
        referenceWidth = width;
        referenceHeight = height;
    }

    // Scale both edges of a capture using the same mapping as the pointer.
    public static int ScaleCoordinate(int value, int reference, int actual) {
        return (int)Math.Round((double)value * actual / reference, MidpointRounding.AwayFromZero);
    }

    // Reproduce the short pointer gesture that exposes Roblox's pickup prompt.
    public static void Aim(IntPtr window, int x, int y) {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous == IntPtr.Zero) throw new InvalidOperationException("Could not enter physical-pixel coordinate mode.");
        try { AimPhysical(window, x, y); }
        finally { SetThreadDpiAwarenessContext(previous); }
    }

    // Keep the pointer coordinates in the same physical pixel space as the capture.
    private static void AimPhysical(IntPtr window, int x, int y) {
        if (referenceWidth != 0) {
            ClientRect bounds;
            if (!GetClientRect(window, out bounds)) throw new InvalidOperationException("Roblox client size is unavailable.");
            x = ScaleCoordinate(x, referenceWidth, bounds.Right);
            y = ScaleCoordinate(y, referenceHeight, bounds.Bottom);
        }
        var point = new Point { X = x, Y = y };
        if (GetForegroundWindow() != window || !ClientToScreen(window, ref point) || !SetCursorPos(point.X, point.Y))
            throw new InvalidOperationException("Could not aim inside the foreground Roblox window.");
        Thread.Sleep(35);
        if (GetForegroundWindow() != window) throw new InvalidOperationException("Roblox lost foreground focus.");
        mouse_event(2, 0, 0, 0, UIntPtr.Zero);
        try {
            Thread.Sleep(35);
            mouse_event(1, 3, -1, 0, UIntPtr.Zero);
            Thread.Sleep(35);
        } finally { mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
    }

    // Turn the third-person camera once after the route reaches a visual waypoint.
    public static void TurnCamera(IntPtr window, int horizontal, int vertical) {
        if (GetForegroundWindow() != window) throw new InvalidOperationException("Roblox lost foreground focus.");
        mouse_event(8, 0, 0, 0, UIntPtr.Zero);
        try {
            Thread.Sleep(75);
            if (GetForegroundWindow() != window) throw new InvalidOperationException("Roblox lost foreground focus.");
            mouse_event(1, horizontal, vertical, 0, UIntPtr.Zero);
            Thread.Sleep(100);
        } finally { mouse_event(16, 0, 0, 0, UIntPtr.Zero); }
    }

    // Capture only the configured client-area region for the current action.
    public static Bitmap Capture(IntPtr window, int x, int y, int width, int height) {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous == IntPtr.Zero) throw new InvalidOperationException("Could not enter physical-pixel coordinate mode.");
        try { return CapturePhysical(window, x, y, width, height); }
        finally { SetThreadDpiAwarenessContext(previous); }
    }

    // Copy physical screen pixels after resolving the client origin in the same coordinate space.
    private static Bitmap CapturePhysical(IntPtr window, int x, int y, int width, int height) {
        ClientRect bounds;
        if (!GetClientRect(window, out bounds)) throw new InvalidOperationException("Roblox client size is unavailable.");
        int outputWidth = width, outputHeight = height;
        if (referenceWidth != 0) {
            outputWidth = Math.Min(width, referenceWidth - x);
            outputHeight = Math.Min(height, referenceHeight - y);
            int left = ScaleCoordinate(x, referenceWidth, bounds.Right);
            int top = ScaleCoordinate(y, referenceHeight, bounds.Bottom);
            width = ScaleCoordinate(x + outputWidth, referenceWidth, bounds.Right) - left;
            height = ScaleCoordinate(y + outputHeight, referenceHeight, bounds.Bottom) - top;
            x = left;
            y = top;
        }
        width = Math.Min(width, bounds.Right - x);
        height = Math.Min(height, bounds.Bottom - y);
        if (width <= 0 || height <= 0) throw new ArgumentException("Capture region is outside the Roblox client.");
        var origin = new Point { X = x, Y = y };
        if (!ClientToScreen(window, ref origin)) throw new InvalidOperationException("Roblox window is unavailable.");
        var bitmap = new Bitmap(width, height);
        try {
            using (var graphics = Graphics.FromImage(bitmap)) {
                graphics.CopyFromScreen(origin.X, origin.Y, 0, 0, bitmap.Size);
            }
            if (referenceWidth != 0 && (width != outputWidth || height != outputHeight)) {
                using (bitmap) return new Bitmap(bitmap, outputWidth, outputHeight);
            }
            return bitmap;
        } catch { bitmap.Dispose(); throw; }
    }

    // Search for a fixed-size reference patch using sampled RGB differences.
    public static int[] Match(Bitmap frame, Bitmap reference) {
        return Match(frame, reference, 2);
    }

    // Broad marker searches can use coarser positions than item aiming.
    public static int[] Match(Bitmap frame, Bitmap reference, int positionStride) {
        int best = int.MaxValue, bestX = -1, bestY = -1;
        int stride = Math.Max(1, Math.Min(reference.Width, reference.Height) / 6);
        int columns = (reference.Width + stride - 1) / stride;
        int rows = (reference.Height + stride - 1) / stride;
        var samples = new Color[columns * rows];
        int index = 0;
        for (int y = 0; y < reference.Height; y += stride)
            for (int x = 0; x < reference.Width; x += stride)
                samples[index++] = reference.GetPixel(x, y);
        int[] pixels = ReadPixels(frame);
        for (int top = 0; top <= frame.Height - reference.Height; top += positionStride) {
            for (int left = 0; left <= frame.Width - reference.Width; left += positionStride) {
                int error = 0;
                index = 0;
                for (int y = 0; y < reference.Height && error < best; y += stride)
                    for (int x = 0; x < reference.Width; x += stride) {
                        int a = pixels[(top + y) * frame.Width + left + x];
                        var b = samples[index++];
                        error += Math.Abs(((a >> 16) & 255) - b.R) + Math.Abs(((a >> 8) & 255) - b.G) + Math.Abs((a & 255) - b.B);
                    }
                if (error < best) { best = error; bestX = left; bestY = top; }
            }
        }
        if (bestX < 0) throw new ArgumentException("Reference must fit inside the capture region.");
        return new[] { best / (samples.Length * 3), bestX + reference.Width / 2, bestY + reference.Height / 2 };
    }

    // Copy bitmap rows once so detection can examine pixels without calling GDI for each sample.
    private static int[] ReadPixels(Bitmap frame) {
        int[] pixels = new int[frame.Width * frame.Height];
        var area = new Rectangle(0, 0, frame.Width, frame.Height);
        var data = frame.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            for (int y = 0; y < frame.Height; y++)
                Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), pixels, y * frame.Width, frame.Width);
        } finally { frame.UnlockBits(data); }
        return pixels;
    }

    // Sample world pixels outside the avatar and HUD to estimate movement from consecutive views.
    public static int[] MotionSample(Bitmap frame) {
        var pixels = ReadPixels(frame);
        int columns = (frame.Width + 7) / 8, rows = (frame.Height + 7) / 8;
        var sample = new int[columns * rows];
        int i = 0;
        for (int y = 0; y < frame.Height; y += 8)
            for (int x = 0; x < frame.Width; x += 8) {
                int rgb = pixels[y * frame.Width + x];
                sample[i++] = (((rgb >> 16) & 255) + ((rgb >> 8) & 255) * 2 + (rgb & 255)) / 4;
            }
        return sample;
    }

    // Compare samples on a 0–255 scale so a stationary view remains near zero.
    public static double MotionDifference(int[] a, int[] b) {
        if (a.Length != b.Length || a.Length == 0) throw new ArgumentException("Motion sample sizes differ.");
        int sum = 0;
        for (int i = 0; i < a.Length; i++) sum += Math.Abs(a[i] - b[i]);
        return (double)sum / a.Length;
    }

    // Measure the green fill in the calibrated health bar, ignoring isolated glyph pixels.
    public static int HealthFill(Bitmap frame) {
        int[] pixels = ReadPixels(frame);
        int longest = 0;
        for (int y = 0; y < frame.Height; y++) {
            int run = 0;
            for (int x = 0; x < frame.Width; x++) {
                int rgb = pixels[y * frame.Width + x];
                int green = (rgb >> 8) & 255;
                if (green >= 145 && green - ((rgb >> 16) & 255) >= 55 && green - (rgb & 255) >= 45) {
                    longest = Math.Max(longest, ++run);
                } else run = 0;
            }
        }
        return 100 * longest / frame.Width;
    }

    // Recognize the F glyph inside its white HUD keycap independently of the label and background.
    public static bool HasPickupKey(Bitmap frame) {
        int width = frame.Width, height = frame.Height;
        int[] pixels = ReadPixels(frame);
        var white = new bool[pixels.Length];
        for (int i = 0; i < pixels.Length; i++) {
            int rgb = pixels[i];
            white[i] = ((rgb >> 16) & 255) >= 215 && ((rgb >> 8) & 255) >= 215 && (rgb & 255) >= 215;
        }
        var component = new int[pixels.Length];
        for (int seed = 0; seed < white.Length; seed++) {
            if (!white[seed]) continue;
            int count = 1, left = width, right = 0, top = height, bottom = 0;
            component[0] = seed;
            white[seed] = false;
            for (int i = 0; i < count; i++) {
                int p = component[i], x = p % width, y = p / width;
                left = Math.Min(left, x); right = Math.Max(right, x);
                top = Math.Min(top, y); bottom = Math.Max(bottom, y);
                if (x > 0) Visit(white, component, p - 1, ref count);
                if (x + 1 < width) Visit(white, component, p + 1, ref count);
                if (y > 0) Visit(white, component, p - width, ref count);
                if (y + 1 < height) Visit(white, component, p + width, ref count);
            }
            int w = right - left + 1, h = bottom - top + 1;
            if (w < 14 || w > 65 || h < 14 || h > 60 || w * 3 < h * 2 || h * 3 < w * 2 || count * 4 < w * h * 3) continue;
            if (left == 0 || right == width - 1 || top == 0 || bottom == height - 1) continue;
            if (DarkKeyPixel(pixels, width, left + w * 53 / 100, top + h * 31 / 100)
                && DarkKeyPixel(pixels, width, left + w * 49 / 100, top + h * 48 / 100)
                && DarkKeyPixel(pixels, width, left + w * 36 / 100, top + h * 65 / 100)
                && !DarkKeyPixel(pixels, width, left + w * 54 / 100, top + h * 65 / 100)) return true;
        }
        return false;
    }

    // Sample the dark glyph rather than comparing a template against the scene behind it.
    private static bool DarkKeyPixel(int[] pixels, int width, int x, int y) {
        int rgb = pixels[y * width + x];
        return ((rgb >> 16) & 255) < 170 && ((rgb >> 8) & 255) < 170 && (rgb & 255) < 170;
    }

    // Find a compact, solid yellow marker at any scale in the configured world-view crop.
    public static int[] FindFuelMarker(Bitmap frame) {
        return FindFuelColor(frame, false);
    }

    // The red can is searched only below the last matched yellow guide marker.
    public static int[] FindFuelCan(Bitmap frame) {
        return FindFuelColor(frame, true);
    }

    // A chain of ground arrows appears after the marked fuel enters the bag.
    public static int[] FindReturnTrail(Bitmap frame) {
        return FindFuelColor(frame, false, true, true, -1000, -1000);
    }

    // Near the generator, the trail sits higher in the view and its arrows are thinner.
    public static int[] FindReturnDirection(Bitmap frame, int originX, int originY) {
        return FindFuelColor(frame, false, true, true, originX, originY);
    }

    // Locate the dark-framed progress bar independently of its fill percentage.
    public static int[] FindGeneratorBar(Bitmap frame) {
        var pixels = ReadPixels(frame);
        int bestWidth = 0, bestX = -1, bestY = -1, bestGreen = 0;
        int previousWidth = 0, previousCenter = -1, matchingRows = 0;
        for (int y = 1; y < frame.Height - 1; y += 3) {
            int row = y * frame.Width;
            int rowWidth = 0, rowCenter = -1, rowGreen = 0;
            int start = -1;
            int green = 0;
            int gap = 0;
            for (int x = 1; x < frame.Width; x++) {
                int rgb = pixels[row + x];
                int r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
                bool greenFill = g >= 205 && r < 55 && b < 55;
                bool fill = (r >= 135 && r <= 180 && Math.Abs(r - g) <= 9 && Math.Abs(g - b) <= 12) || greenFill;
                if (fill) {
                    if (start < 0) start = x;
                    if (greenFill) green++;
                    gap = 0;
                    continue;
                }
                if (start < 0) continue;
                if (gap < 5 && (b >= 90 || g >= 95)) { gap++; continue; }
                int end = x - gap;
                int width = end - start;
                bool leftEdge = false, rightEdge = false;
                if (width >= 270 && width > rowWidth) {
                    for (int offset = 0; offset < 8; offset++) {
                        if (start > offset && (pixels[row + start - offset - 1] & 255) < 100) leftEdge = true;
                        if (end + offset < frame.Width && (pixels[row + end + offset] & 255) < 100) rightEdge = true;
                    }
                }
                if (leftEdge && rightEdge) {
                    rowWidth = width; rowCenter = (start + end) / 2; rowGreen = green;
                }
                start = -1;
                green = 0;
                gap = 0;
            }
            if (rowWidth == 0) matchingRows = 0;
            else if (Math.Abs(rowWidth - previousWidth) <= 9 && Math.Abs(rowCenter - previousCenter) <= 5) matchingRows++;
            else matchingRows = 1;
            if (matchingRows >= 6 && rowWidth > bestWidth) {
                bestWidth = rowWidth; bestX = rowCenter; bestY = y - 7; bestGreen = rowGreen;
            }
            previousWidth = rowWidth;
            previousCenter = rowCenter;
        }
        return new[] { bestWidth, bestX, bestY, bestWidth > 0 ? (100 * bestGreen / bestWidth) : -1 };
    }

    // Rank compact connected components without depending on a fixed object scale.
    private static int[] FindFuelColor(Bitmap frame, bool redCan, bool returnTrail = false, bool allowThinArrows = false, int originX = 0, int originY = 0) {
        int stride = allowThinArrows ? 2 : 3;
        int width = frame.Width / stride, height = frame.Height / stride;
        var pixels = ReadPixels(frame);
        var yellow = new bool[width * height];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int rgb = pixels[y * stride * frame.Width + x * stride];
                int red = (rgb >> 16) & 255, green = (rgb >> 8) & 255, blue = rgb & 255;
                yellow[y * width + x] = redCan
                    ? red >= 120 && red - green >= 70 && red - blue >= 65
                    : red >= (returnTrail ? 185 : 235) && green >= (returnTrail ? 155 : 215) && blue <= 80;
            }
        var queue = new int[yellow.Length];
        int bestCount = 0, bestX = -1, bestY = -1;
        int trailPieces = 0;
        for (int seed = 0; seed < yellow.Length; seed++) {
            if (!yellow[seed]) continue;
            int count = 1, left = width, right = 0, top = height, bottom = 0;
            queue[0] = seed;
            yellow[seed] = false;
            for (int i = 0; i < count; i++) {
                int p = queue[i], x = p % width, y = p / width;
                left = Math.Min(left, x); right = Math.Max(right, x);
                top = Math.Min(top, y); bottom = Math.Max(bottom, y);
                if (x > 0) Visit(yellow, queue, p - 1, ref count);
                if (x + 1 < width) Visit(yellow, queue, p + 1, ref count);
                if (y > 0) Visit(yellow, queue, p - width, ref count);
                if (y + 1 < height) Visit(yellow, queue, p + width, ref count);
            }
            int w = right - left + 1, h = bottom - top + 1;
            if (returnTrail) {
                int minWidth = allowThinArrows ? 2 : 8;
                int aspect = allowThinArrows ? 7 : 3;
                bool shapedLikeArrow = count * 3 >= w * h && (allowThinArrows && w <= 5 || count * 5 <= w * h * 4);
                if (w >= minWidth && h >= 4 && w <= h * 6 && h <= w * aspect && shapedLikeArrow) {
                    trailPieces++;
                    int centerX = (left + right) * stride / 2, centerY = (top + bottom) * stride / 2;
                    bool overAvatar = allowThinArrows && Math.Abs(centerX - originX) < 150 && Math.Abs(centerY - originY) < 130;
                    if (!overAvatar && count > bestCount) {
                        bestCount = count;
                        bestX = centerX;
                        bestY = centerY;
                    }
                }
                continue;
            }
            if (w < 6 || h < 5 || w > h * (redCan ? 4 : 2) || h > w * 2 || count * (redCan ? 4 : 2) < w * h || count <= bestCount) continue;
            if (left == 0 || top == 0 || right == width - 1 || (!redCan && bottom == height - 1)) continue;
            if (!redCan && !HasFuelArrowShape(queue, count, width, left, top, w, h)) continue;
            bestCount = count;
            bestX = (left + right) * stride / 2;
            bestY = (top + bottom) * stride / 2;
            if (redCan) {
                int aimRow = top + Math.Min(3, h / 4);
                int nearest = int.MaxValue;
                int aimX = bestX;
                for (int i = 0; i < count; i++) {
                    int px = queue[i] % width, py = queue[i] / width;
                    int distance = Math.Abs(py - aimRow) * width + Math.Abs(px * stride - bestX);
                    if (distance >= nearest) continue;
                    nearest = distance;
                    aimX = px * stride;
                    bestY = py * stride;
                }
                bestX = aimX;
            }
        }
        return new[] { bestCount == 0 || (returnTrail && trailPieces < 3) ? 255 : 0, bestX, bestY };
    }

    // The fuel arrow has two yellow shoulders above a central notch and tapers below its broad body.
    private static bool HasFuelArrowShape(int[] component, int count, int stride, int left, int top, int width, int height) {
        int firstShoulderRow = Math.Max(1, height / 8);
        int lastShoulderRow = Math.Max(firstShoulderRow, height / 4);
        int bodyRow = height / 2;
        int tipRow = height - 1;
        var shoulders = new int[lastShoulderRow - firstShoulderRow + 1];
        int body = 0, tip = 0;
        for (int i = 0; i < count; i++) {
            int y = component[i] / stride - top;
            if (y >= firstShoulderRow && y <= lastShoulderRow) {
                int x = component[i] % stride - left;
                int band = x * 5 < width * 2 ? 1 : x * 5 >= width * 3 ? 2 : 4;
                shoulders[y - firstShoulderRow] |= band;
            } else if (y == bodyRow) body++;
            else if (y == tipRow) tip++;
        }
        return Array.IndexOf(shoulders, 3) >= 0 && body * 3 >= width * 2 && tip * 2 <= width;
    }

    // Mark connected pixels once as the component is traversed.
    private static void Visit(bool[] mask, int[] queue, int pixel, ref int count) {
        if (!mask[pixel]) return;
        mask[pixel] = false;
        queue[count++] = pixel;
    }

    // Send a held movement or interaction key with its hardware scan code.
    public static void Key(byte code, bool up) {
        var keyboard = new Keyboard { ScanCode = (ushort)MapVirtualKey(code, 0), Flags = up ? 10u : 8u };
        var input = new Input { Type = 1, Data = new InputData { Keyboard = keyboard } };
        if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input))) != 1)
            throw new InvalidOperationException("Windows SendInput failed: " + Marshal.GetLastWin32Error());
    }
}
'@

if ($SelfTest) {
    $frame = [Drawing.Bitmap]::new(96, 72)
    $graphics = [Drawing.Graphics]::FromImage($frame)
    try {
        $graphics.Clear([Drawing.Color]::Black)
        $graphics.FillRectangle([Drawing.Brushes]::Orange, 40, 28, 12, 10)
        $reference = $frame.Clone([Drawing.Rectangle]::new(40, 28, 12, 10), $frame.PixelFormat)
        try {
            $match = [RobloxRouteNative]::Match($frame, $reference)
            if ($match[0] -ne 0 -or $match[1] -ne 46 -or $match[2] -ne 33) { throw 'Reference match test failed.' }
            'Reference match test passed.'
        } finally { $reference.Dispose() }
    } finally { $graphics.Dispose(); $frame.Dispose() }
    return
}

if ($ReferenceWidth -or $ReferenceHeight) {
    [RobloxRouteNative]::UseReferenceSize($ReferenceWidth, $ReferenceHeight)
}
$window = (Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue | Where-Object MainWindowHandle | Select-Object -First 1).MainWindowHandle
if (-not $window) { throw 'Roblox window is unavailable.' }
if ($CaptureProbe) {
    if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox must be in the foreground for the capture probe.' }
    $initial = [RobloxRouteNative]::Capture($window, 64, 64, 160, 120)
    try { $reference = $initial.Clone([Drawing.Rectangle]::new(40, 30, 24, 24), $initial.PixelFormat) }
    finally { $initial.Dispose() }
    try {
        $samples = foreach ($index in 1..20) {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
            $frame = [RobloxRouteNative]::Capture($window, 64, 64, 160, 120)
            try { $score, $x, $y = [RobloxRouteNative]::Match($frame, $reference) }
            finally { $frame.Dispose() }
            [pscustomobject]@{ Milliseconds = [Math]::Round($clock.Elapsed.TotalMilliseconds, 2); Error = $score; X = $x; Y = $y }
        }
        $samples | Format-Table -AutoSize
    } finally { $reference.Dispose() }
    return
}

if (-not $RouteJson) { throw 'Pass a calibrated route as -RouteJson or use -SelfTest.' }
$route = ConvertFrom-Json -InputObject $RouteJson
$route = @($route)
$pickupSequence = @('aimFuel', 'confirmFuelPrompt', 'confirmBag')
for ($index = 0; $index -lt $route.Count; $index++) {
    $action = [string]$route[$index].action
    if ($action -in $pickupSequence) {
        $start = $index - [Array]::IndexOf($pickupSequence, $action)
        if ($start -lt 0 -or $start + 2 -ge $route.Count -or
            ($route[$start..($start + 2)].action -join ',') -ne ($pickupSequence -join ',')) {
            throw 'A pickup requires adjacent aimFuel, confirmFuelPrompt, and confirmBag steps.'
        }
        if ($route[$index].keys) { throw 'Pickup confirmation steps cannot hold movement or interaction keys.' }
    }
    if ($action -eq 'deliverFuel' -and ($index + 1 -ge $route.Count -or $route[$index + 1].action -ne 'confirmDelivery')) {
        throw 'Fuel delivery requires an immediately following confirmDelivery step.'
    }
    if ($action -eq 'confirmDelivery' -and ($index -eq 0 -or $route[$index - 1].action -ne 'deliverFuel' -or $route[$index].keys)) {
        throw 'Delivery confirmation must follow deliverFuel and cannot issue input.'
    }
}
$keys = @{ w = 87; a = 65; s = 83; d = 68; f = 70; shift = 16; space = 32; '1' = 49 }
$held = @()
$routeClock = [Diagnostics.Stopwatch]::new()
$deliveryConfirmed = $false
$fillBeforeDelivery = $null
$outbound = [Collections.Generic.List[object]]::new()
$lastMarker = $null
$lastCanRegion = $null
$lastCanPoint = $null
$reverseKey = @{ w = 's'; s = 'w'; a = 'd'; d = 'a'; shift = 'shift' }

# Release outgoing keys before issuing a correction or ending the route.
function Set-HeldKeys([string[]]$Next) {
    if ($DryRun) { return }
    foreach ($key in @($script:held)) {
        if ($key -notin $Next) {
            [RobloxRouteNative]::Key($keys[$key], $true)
            $script:held = @($script:held | Where-Object { $_ -ne $key })
        }
    }
    foreach ($key in $Next) {
        if ($key -notin $script:held) {
            [RobloxRouteNative]::Key($keys[$key], $false)
            if ($key -in @('w', 'a', 's', 'd') -and -not $routeClock.IsRunning) { $routeClock.Start() }
            $script:held += $key
        }
    }
}

try {
    foreach ($step in $route) {
        if ($step.action -eq 'clearGenerator') {
            if ($DryRun) { continue }
            $next = @($step.keys)
            foreach ($key in $next) { if (-not $reverseKey.ContainsKey($key)) { throw "Unsupported departure key: $key" } }
            $duration = [Math]::Min(1100, [int]$step.durationMs)
            if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
            Set-HeldKeys $next
            $departureClock = [Diagnostics.Stopwatch]::StartNew()
            while ($departureClock.ElapsedMilliseconds -lt $duration) {
                if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                Start-Sleep -Milliseconds 15
            }
            Set-HeldKeys @()
            $outbound.Add(@{ Keys = $next; Duration = $departureClock.ElapsedMilliseconds })
            [pscustomobject]@{ Step = $step.name; ElapsedMs = $departureClock.ElapsedMilliseconds }
            continue
        }
        if ($step.action -eq 'returnPath') {
            if ($DryRun) { continue }
            if ($outbound.Count -eq 0) { throw 'No outbound movement was recorded.' }
            $returnClock = [Diagnostics.Stopwatch]::StartNew()
            $replayedSegments = 0
            $replayInterrupted = $false
            $motionSample = $null
            $motionAt = 0
            $quietSince = -1
            for ($index = $outbound.Count - 1; $index -ge 0; $index--) {
                $segment = $outbound[$index]
                $segmentClock = [Diagnostics.Stopwatch]::StartNew()
                $next = @($segment.Keys | ForEach-Object { $reverseKey[$_] })
                if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                Set-HeldKeys $next
                while ($segmentClock.ElapsedMilliseconds -lt $segment.Duration) {
                    if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                    $now = $returnClock.ElapsedMilliseconds
                    if ($step.recoveryRegion -and $now - $motionAt -ge 120) {
                        $probe = $step.recoveryRegion
                        $world = [RobloxRouteNative]::Capture($window, $probe.x, $probe.y, $probe.width, $probe.height)
                        try { $sample = [RobloxRouteNative]::MotionSample($world) }
                        finally { $world.Dispose() }
                        if ($motionSample -and [RobloxRouteNative]::MotionDifference($motionSample, $sample) -le 1.8) {
                            if ($quietSince -lt 0) { $quietSince = $motionAt }
                            if ($now - $quietSince -ge 420) {
                                $replayInterrupted = $true
                                break
                            }
                        } else { $quietSince = -1 }
                        $motionSample = $sample
                        $motionAt = $now
                    }
                    Start-Sleep -Milliseconds ([Math]::Min(20, [Math]::Max(1, $segment.Duration - $segmentClock.ElapsedMilliseconds)))
                }
                if ($replayInterrupted) { break }
                $replayedSegments++
            }
            Set-HeldKeys @()
            [pscustomobject]@{ Step = $step.name; ReversedSegments = $replayedSegments; ReplayInterrupted = $replayInterrupted; ElapsedMs = $returnClock.ElapsedMilliseconds }
            continue
        }
        $region = $step.region
        $trackingMarker = $step.action -eq 'followFuelMarker'
        $locatingCan = $step.action -eq 'aimFuel' -and -not $step.reference
        $confirmingTrail = $step.action -eq 'confirmBag' -and -not $step.reference
        $checkingPickupKey = $step.action -eq 'confirmFuelPrompt' -and $step.pickupKeyRegion
        $followingTrail = $step.action -eq 'followReturnTrail'
        $aligningGenerator = $step.action -eq 'alignGenerator'
        $checkingGenerator = $step.action -in @('followReturnTrail', 'deliverFuel', 'confirmDelivery') -and -not $step.reference
        if ($locatingCan) {
            if (-not $lastMarker) { throw 'Fuel can search requires a preceding successful marker step.' }
            $region = @{ x = [Math]::Max(0, $lastMarker.X - 144); y = $lastMarker.Y + 22; width = 288; height = 520 }
        }
        $reference = $null
        if ($checkingPickupKey) { $region = $step.pickupKeyRegion }
        if (-not ($trackingMarker -or $locatingCan -or $confirmingTrail -or $checkingPickupKey -or $aligningGenerator -or $checkingGenerator)) { $reference = [Drawing.Bitmap]::new([string]$step.reference) }
        try {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $frames = 0
            $matched = $false
            $score = $null
            $x = $null
            $y = $null
            $segmentStart = 0
            $turnedForTrail = $false
            $aimRetry = 0
            $motionSample = $null
            $motionAt = 0
            $quietSince = -1
            $detourBackUntil = 0
            $detourUntil = 0
            $detours = 0
            $healthAt = -100
            $lastHealth = -1
            $escapeUntil = 0
            $escapes = 0
            $limit = 5000
            if ($trackingMarker -or $followingTrail) { $limit = 12000 }
            $timeout = [Math]::Min($limit, [int]$step.timeoutMs)
            while ($clock.ElapsedMilliseconds -lt $timeout) {
                if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                $frame = [RobloxRouteNative]::Capture($window, $region.x, $region.y, $region.width, $region.height)
                try {
                    if ($trackingMarker) { $score, $x, $y = [RobloxRouteNative]::FindFuelMarker($frame) }
                    elseif ($locatingCan) { $score, $x, $y = [RobloxRouteNative]::FindFuelCan($frame) }
                    elseif ($checkingPickupKey) {
                        $score = 255
                        if ([RobloxRouteNative]::HasPickupKey($frame)) { $score = 0 }
                    }
                    elseif ($confirmingTrail) {
                        $score, $x, $y = [RobloxRouteNative]::FindReturnTrail($frame)
                        if ($score -eq 0 -and $lastCanRegion) {
                            $canFrame = [RobloxRouteNative]::Capture($window, $lastCanRegion.x, $lastCanRegion.y, $lastCanRegion.width, $lastCanRegion.height)
                            try { if ([RobloxRouteNative]::FindFuelCan($canFrame)[0] -eq 0) { $score = 255 } }
                            finally { $canFrame.Dispose() }
                        }
                    }
                    elseif ($aligningGenerator -or $checkingGenerator) {
                        $barWidth, $x, $y, $barFill = [RobloxRouteNative]::FindGeneratorBar($frame)
                        $score = 255
                        if ($barWidth) { $score = 0 }
                    }
                    elseif ($followingTrail) { $score, $x, $y = [RobloxRouteNative]::Match($frame, $reference, 6) }
                    else { $score, $x, $y = [RobloxRouteNative]::Match($frame, $reference) }
                }
                finally { $frame.Dispose() }
                $frames++
                $aligned = [Math]::Abs($x - $step.targetX) -le $step.tolerance
                $arrived = [Math]::Abs($y - $step.targetY) -le $step.tolerance
                if ($trackingMarker) { $arrived = $y -ge $step.targetY }
                if ($aligningGenerator) { $arrived = $barWidth -ge $step.minimumWidth }
                if ($checkingGenerator) {
                    $arrived = $barWidth -ge $step.minimumWidth
                    if ($step.action -eq 'confirmDelivery') {
                        $arrived = $arrived -and $null -ne $fillBeforeDelivery -and [Math]::Abs($barFill - $fillBeforeDelivery) -ge 10
                    }
                }
                if ($locatingCan -or $confirmingTrail -or $checkingPickupKey) { $aligned = $score -eq 0; $arrived = $aligned }
                if ($score -le $step.maxError -and $aligned -and $arrived) {
                    $matched = $true
                    break
                }
                if ($DryRun) { break }
                if ($step.action -eq 'confirmFuelPrompt' -and $lastCanPoint -and $aimRetry -lt 3 -and $clock.ElapsedMilliseconds -ge 220 * ($aimRetry + 1)) {
                    $offsets = @(@(-26, 25), @(25, 23), @(0, 48))
                    $offset = $offsets[$aimRetry]
                    [RobloxRouteNative]::Aim($window, $lastCanPoint.X + $offset[0], $lastCanPoint.Y + $offset[1])
                    $aimRetry++
                }
                $next = @($step.keys | Where-Object { $_ })
                if ($aligningGenerator) {
                    $next = @()
                    if ($barWidth) {
                        if ($x -lt $step.targetX - $step.tolerance) { $next = @('a') }
                        elseif ($x -gt $step.targetX + $step.tolerance) { $next = @('d') }
                        elseif (-not $arrived) { $next = @('w') }
                    }
                }
                if ($followingTrail -and $step.alignForDelivery -and $barWidth -ge 270) {
                    $next = @()
                    if ($x -lt $step.targetX - $step.tolerance) { $next += 'a' }
                    elseif ($x -gt $step.targetX + $step.tolerance) { $next += 'd' }
                    if (-not $arrived) { $next += 'w' }
                }
                elseif ($followingTrail) {
                    $trail = $step.trailRegion
                    $trailFrame = [RobloxRouteNative]::Capture($window, $trail.x, $trail.y, $trail.width, $trail.height)
                    try { $signal, $trailX, $trailY = [RobloxRouteNative]::FindReturnDirection($trailFrame, $step.trailOriginX - $trail.x, $step.trailOriginY - $trail.y) }
                    finally { $trailFrame.Dispose() }
                    $next = @()
                    if ($signal -eq 0) {
                        $dx = $trail.x + $trailX - $step.trailOriginX
                        $dy = $trail.y + $trailY - $step.trailOriginY
                        if (-not $turnedForTrail -and [Math]::Abs($dx) -le 120 -and $dy -gt 60) {
                            if ($TraceReturn) { Write-Host "Return $($clock.ElapsedMilliseconds) ms: camera turn, dx=$dx dy=$dy" }
                            Set-HeldKeys @()
                            [RobloxRouteNative]::TurnCamera($window, $ReturnTurnX, 0)
                            $turnedForTrail = $true
                            continue
                        }
                        if ($dx -lt -100) { $next += 'a' }
                        elseif ($dx -gt 100) { $next += 'd' }
                        if ($dy -lt -60) { $next += 'w' }
                        elseif ($dy -gt 60) { $next += 's' }
                    }
                    if ($TraceReturn -and ($held -join '+') -ne ($next -join '+')) {
                        Write-Host "Return $($clock.ElapsedMilliseconds) ms: keys=$($next -join '+') signal=$signal x=$trailX y=$trailY targetError=$score"
                    }
                }
                if ($trackingMarker -and $score -gt $step.maxError) { $next = @() }
                if ($score -le $step.maxError -and ($step.steer -or $trackingMarker) -and -not $aligned) {
                    $next = @($next | Where-Object { $_ -notin @('a', 'd') })
                    if ($trackingMarker) { $next = @() }
                    if ($x -lt $step.targetX) { $next += 'a' } else { $next += 'd' }
                }
                $now = $clock.ElapsedMilliseconds
                if ($step.healthRegion -and $now - $healthAt -ge 100) {
                    $probe = $step.healthRegion
                    $healthFrame = [RobloxRouteNative]::Capture($window, $probe.x, $probe.y, $probe.width, $probe.height)
                    try { $health = [RobloxRouteNative]::HealthFill($healthFrame) }
                    finally { $healthFrame.Dispose() }
                    if ($now -ge $escapeUntil -and $lastHealth - $health -ge 5) {
                        $escapeUntil = $now + 580
                        $escapes++
                        $motionSample = $null
                        $quietSince = -1
                    }
                    $healthAt = $now
                    $lastHealth = $health
                }
                if ($now -lt $escapeUntil) {
                    $next = @('s', 'd', 'shift', 'space')
                } elseif ($step.recoveryRegion) {
                    if ($now -lt $detourBackUntil) {
                        $next = @('s')
                    } elseif ($now -lt $detourUntil) {
                        $next = @($detourKey)
                    } elseif (@($held | Where-Object { $_ -in @('w','a','s','d') }).Count -and $now - $motionAt -ge 120) {
                        $probe = $step.recoveryRegion
                        $world = [RobloxRouteNative]::Capture($window, $probe.x, $probe.y, $probe.width, $probe.height)
                        try { $sample = [RobloxRouteNative]::MotionSample($world) }
                        finally { $world.Dispose() }
                        if ($motionSample -and [RobloxRouteNative]::MotionDifference($motionSample, $sample) -le 1.8) {
                            if ($quietSince -lt 0) { $quietSince = $motionAt }
                            if ($now - $quietSince -ge 420 -and $detours -lt 2) {
                                $detourKey = 'a'
                                if ($held -contains 'a' -or ($detours -eq 1 -and $held -notcontains 'd')) { $detourKey = 'd' }
                                $detourBackUntil = $now + 500
                                $detourUntil = $detourBackUntil + 950
                                $detours++
                                $next = @('s')
                                $sample = $null
                                $quietSince = -1
                            }
                        } else { $quietSince = -1 }
                        $motionSample = $sample
                        $motionAt = $now
                    } elseif (-not @($held | Where-Object { $_ -in @('w','a','s','d') }).Count) {
                        $motionSample = $null
                        $quietSince = -1
                    }
                }
                foreach ($key in $next) { if (-not $keys.ContainsKey($key)) { throw "Unsupported route key: $key" } }
                if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                if ($trackingMarker -and ($held -join '+') -ne ($next -join '+')) {
                    if ($held.Count) { $outbound.Add(@{ Keys = @($held | Where-Object { $reverseKey.ContainsKey($_) }); Duration = $clock.ElapsedMilliseconds - $segmentStart }) }
                    $segmentStart = $clock.ElapsedMilliseconds
                }
                Set-HeldKeys $next
                Start-Sleep -Milliseconds 15
            }
            if ($trackingMarker -and $held.Count) { $outbound.Add(@{ Keys = @($held | Where-Object { $reverseKey.ContainsKey($_) }); Duration = $clock.ElapsedMilliseconds - $segmentStart }) }
            Set-HeldKeys @()
            if ($matched -and $trackingMarker) { $lastMarker = @{ X = $region.x + $x; Y = $region.y + $y } }
            if ($matched -and $locatingCan) { $lastCanRegion = $region }
            if ($matched -and -not $DryRun) {
                if ([RobloxRouteNative]::GetForegroundWindow() -ne $window) { throw 'Roblox lost foreground focus.' }
                switch ($step.action) {
                    'aimFuel' {
                        $lastCanPoint = @{ X = $region.x + $x; Y = $region.y + $y }
                        [RobloxRouteNative]::Aim($window, $lastCanPoint.X, $lastCanPoint.Y)
                    }
                    'turnCamera' { [RobloxRouteNative]::TurnCamera($window, $step.lookX, $step.lookY) }
                }
                if ($step.action -in @('confirmFuelPrompt', 'deliverFuel')) {
                    if ($checkingGenerator) { $fillBeforeDelivery = $barFill }
                    Set-HeldKeys @('f')
                    try { Start-Sleep -Milliseconds 140 }
                    finally { Set-HeldKeys @() }
                }
                if ($step.action -eq 'confirmDelivery') { $deliveryConfirmed = $true }
            }
            [pscustomobject]@{ Step = $step.name; Matched = $matched; Frames = $frames; ElapsedMs = $clock.ElapsedMilliseconds; LastError = $score; MatchX = $x; MatchY = $y; Detours = $detours; DamageEscapes = $escapes }
            if (-not $matched -and -not $DryRun) { break }
        } finally { if ($reference) { $reference.Dispose() } }
    }
} finally {
    $routeClock.Stop()
    Set-HeldKeys @()
    if (-not $DryRun) {
        [pscustomobject]@{ Summary = 'Movement input to final confirmation'; DeliveryConfirmed = $deliveryConfirmed; ElapsedMs = $routeClock.ElapsedMilliseconds }
    }
}
