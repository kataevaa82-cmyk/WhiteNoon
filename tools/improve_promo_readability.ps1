$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class PromoReadability
{
    private static double Feather(double x, double y, double cx, double cy, double rx, double ry, double strength)
    {
        double dx = (x - cx) / rx;
        double dy = (y - cy) / ry;
        double distance = Math.Sqrt(dx * dx + dy * dy);
        if (distance >= 1.0) return 0.0;
        double feather = 1.0 - distance;
        return strength * feather * feather * (3.0 - 2.0 * feather);
    }

    private static bool IsTitlePixel(byte red, byte green, byte blue)
    {
        // The title is warm ivory. Preserve its antialiased edge while allowing the
        // dark scenery and its existing shadow to receive the new local vignette.
        int luminance = (red * 54 + green * 183 + blue * 19) >> 8;
        return luminance > 145 && red > 165 && green > 135 && red >= green && green + 12 >= blue;
    }

    private static bool IsLogoPixel(byte[] logoPixels, int logoStride, int logoWidth, int logoHeight,
                                    int x, int y, Rectangle logoRect)
    {
        if (!logoRect.Contains(x, y)) return false;
        int lx = (x - logoRect.X) * logoWidth / logoRect.Width;
        int ly = (y - logoRect.Y) * logoHeight / logoRect.Height;
        // A one-source-pixel dilation protects the antialiased fringe of the mark.
        for (int oy = -1; oy <= 1; oy++)
        {
            int sy = Math.Max(0, Math.Min(logoHeight - 1, ly + oy));
            for (int ox = -1; ox <= 1; ox++)
            {
                int sx = Math.Max(0, Math.Min(logoWidth - 1, lx + ox));
                if (logoPixels[sy * logoStride + sx * 4 + 3] > 8) return true;
            }
        }
        return false;
    }

    public static void Apply(string targetPath, string logoPath, Rectangle logoRect, Rectangle titleRect,
                             double logoCx, double logoCy, double logoRx, double logoRy, double logoStrength,
                             double titleCx, double titleCy, double titleRx, double titleRy, double titleStrength)
    {
        string temporaryPath = targetPath + ".readability.tmp";
        using (var input = new Bitmap(targetPath))
        using (var logoInput = new Bitmap(logoPath))
        using (var image = new Bitmap(input.Width, input.Height, PixelFormat.Format32bppArgb))
        using (var logo = new Bitmap(logoInput.Width, logoInput.Height, PixelFormat.Format32bppArgb))
        {
            using (Graphics graphics = Graphics.FromImage(image)) graphics.DrawImageUnscaled(input, 0, 0);
            using (Graphics graphics = Graphics.FromImage(logo)) graphics.DrawImageUnscaled(logoInput, 0, 0);

            Rectangle imageBounds = new Rectangle(0, 0, image.Width, image.Height);
            Rectangle logoBounds = new Rectangle(0, 0, logo.Width, logo.Height);
            BitmapData imageData = image.LockBits(imageBounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            BitmapData logoData = logo.LockBits(logoBounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte[] pixels = new byte[Math.Abs(imageData.Stride) * image.Height];
                byte[] logoPixels = new byte[Math.Abs(logoData.Stride) * logo.Height];
                Marshal.Copy(imageData.Scan0, pixels, 0, pixels.Length);
                Marshal.Copy(logoData.Scan0, logoPixels, 0, logoPixels.Length);

                for (int y = 0; y < image.Height; y++)
                {
                    for (int x = 0; x < image.Width; x++)
                    {
                        int offset = y * imageData.Stride + x * 4;
                        byte blue = pixels[offset];
                        byte green = pixels[offset + 1];
                        byte red = pixels[offset + 2];

                        bool preserveLogo = IsLogoPixel(logoPixels, logoData.Stride, logo.Width, logo.Height, x, y, logoRect);
                        bool preserveTitle = titleRect.Contains(x, y) && IsTitlePixel(red, green, blue);
                        if (preserveLogo || preserveTitle) continue;

                        double amount = Math.Max(
                            Feather(x, y, logoCx, logoCy, logoRx, logoRy, logoStrength),
                            Feather(x, y, titleCx, titleCy, titleRx, titleRy, titleStrength));
                        if (amount <= 0.0) continue;
                        double multiplier = 1.0 - amount;
                        pixels[offset] = (byte)Math.Round(blue * multiplier);
                        pixels[offset + 1] = (byte)Math.Round(green * multiplier);
                        pixels[offset + 2] = (byte)Math.Round(red * multiplier);
                    }
                }

                Marshal.Copy(pixels, 0, imageData.Scan0, pixels.Length);
            }
            finally
            {
                image.UnlockBits(imageData);
                logo.UnlockBits(logoData);
            }

            if (Path.GetExtension(targetPath).Equals(".jpg", StringComparison.OrdinalIgnoreCase) ||
                Path.GetExtension(targetPath).Equals(".jpeg", StringComparison.OrdinalIgnoreCase))
            {
                ImageCodecInfo codec = null;
                foreach (ImageCodecInfo candidate in ImageCodecInfo.GetImageEncoders())
                    if (candidate.MimeType == "image/jpeg") codec = candidate;
                using (var parameters = new EncoderParameters(1))
                {
                    parameters.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 96L);
                    image.Save(temporaryPath, codec, parameters);
                }
            }
            else
            {
                using (var flattened = new Bitmap(image.Width, image.Height, PixelFormat.Format24bppRgb))
                {
                    using (Graphics graphics = Graphics.FromImage(flattened))
                    {
                        graphics.Clear(Color.Black);
                        graphics.DrawImageUnscaled(image, 0, 0);
                    }
                    flattened.Save(temporaryPath, ImageFormat.Png);
                }
            }
        }
        File.Copy(temporaryPath, targetPath, true);
        File.Delete(temporaryPath);
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

$workspace = Split-Path -Parent $PSScriptRoot
$promoRoot = Join-Path $workspace "promo\yandex"
$logoPath = Join-Path $workspace "assets\branding\white_noon_logo_mark.png"
$backupRoot = Join-Path $workspace "build\promo_originals"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$targets = @(
    "cover_ru_800x470.png",
    "cover_en_800x470.png",
    "showcase_ru_1560x520.jpg",
    "showcase_en_1560x520.jpg"
)
foreach ($name in $targets) {
    $sourcePath = Join-Path $promoRoot $name
    $backupPath = Join-Path $backupRoot $name
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $sourcePath -Destination $backupPath
    }
    else {
        Copy-Item -LiteralPath $backupPath -Destination $sourcePath -Force
    }
}

foreach ($name in @("cover_ru_800x470.png", "cover_en_800x470.png")) {
    $targetPath = Join-Path $promoRoot $name
    [PromoReadability]::Apply(
        $targetPath,
        $logoPath,
        [System.Drawing.Rectangle]::new(220, 207, 360, 180),
        [System.Drawing.Rectangle]::new(185, 380, 430, 60),
        400, 298, 245, 150, 0.28,
        400, 410, 285, 92, 0.40
    )
}

foreach ($name in @("showcase_ru_1560x520.jpg", "showcase_en_1560x520.jpg")) {
    $targetPath = Join-Path $promoRoot $name
    [PromoReadability]::Apply(
        $targetPath,
        $logoPath,
        [System.Drawing.Rectangle]::new(60, 34, 520, 260),
        [System.Drawing.Rectangle]::new(60, 345, 530, 80),
        315, 160, 335, 215, 0.22,
        315, 385, 350, 105, 0.34
    )
}

Write-Host "Promo readability pass completed for 4 localized assets."
