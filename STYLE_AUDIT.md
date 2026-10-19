# 菜单栏样式校准

## 当前版本 1.0.5

用户确认文字及间距正确，并要求仅将 Codex 图标恢复为正常菜单栏大小。因此图标改为 16pt，图像占位宽度从 11pt 增至 16.5pt，保留原校准的尾部留白。文字仍为 13pt SF 常规字重，可见间隔复测仍为 8px（2x），图标不会覆盖或挤占该间隔。下面的天气高度一致要求属于 1.0.4 历史验收，已被此新要求替代。

当前审查使用 `audit-weather.py 原截图路径 输出目录 --standard-icon`，分别检查正常尺寸图标及已确认的字体、间隔。1.0.5 的渲染与结果保存在 `build/weather-calibration/v1.0.5/`。

## 1.0.4 历史校准

本次以用户提供的 392×68 原始截图为外部基准，不缩放截图，不用视觉印象代替测量。以下像素值均为 2x 截图中的可见像素，并非控件名义尺寸。

| 项目 | 截图中的天气 | 修正后源码渲染 |
| --- | ---: | ---: |
| 整组可见高度 | 22px | 22px |
| 图标可见高度 | 21px | 21px |
| 图标到首位数字可见间隔 | 8px | 8px |
| `5°C` 字形外接框 | 44×21px | 44×21px |

保留原圆润花形终端图标，保持正方形比例。天气云朵本身是横向形状，因此不把终端图标拉伸成云朵的宽高比。插件只有内容总宽度增加。

字体候选比较包括：两种系统数字排版、12–14pt（0.25pt 步进）、regular/medium/semibold 三种字重，以及四种横向与四种纵向绘制相位，共 864 组。

用同样的 `5°C` 比较字形，只允许平移和拟合单一前景亮度，不允许缩放、加粗、拉伸或局部修补。最佳候选为 SF 13pt regular 等宽数字，归一化平方误差 0.004518；13pt medium 为 0.035965，上版 14pt medium 为 0.288208。误差不是“像素完全相同”或相似度百分比的声明。

原生 NSStatusBarButton 的 image/title 逻辑间距独立实测为 2pt。结合图标可见边界和数字侧边留白，增加 1pt 前置排版间距，渲染得到 8px 可见间隔。圆形重置箭头在 13pt 时会超过目标高度，因此单独采用 12.5pt 并下移 0.5pt，使其留在相同的整组可见高度内。

## 对抗性检查

除了检查正确版本，另行编译四个故意改错的临时版本，要求审查脚本能够拒绝它们。临时版本不会安装。

| 故意注入的错误 | 结果 |
| --- | --- |
| 恢复 14pt medium | 拒绝：高度、间隔、字形尺寸与轮廓不符 |
| 恢复 18pt 大图标 | 拒绝：整组高度、图标高度与间隔不符 |
| 删除图标间距修正 | 拒绝：图标与数字间隔不符 |
| 恢复未校准的重置箭头 | 拒绝：整组高度不符 |

正确版本通过全部八项检查。审查基准来自用户截图，字体大小、图标高度与间距的预期值不是从当前实现常量直接复制的。

## 复现

使用当前 Mac 的 AppKit 生成离屏组件，再读取原始截图进行对比：

```sh
xcrun swiftc -module-cache-path build/module-cache \
  Sources/StatusAppearance.swift scripts/StyleAudit/main.swift \
  -o build/weather-calibration/style-audit
build/weather-calibration/style-audit build/weather-calibration/final
python3 scripts/audit-weather.py /absolute/path/to/original-reference.png \
  build/weather-calibration/final
```

Python 审查脚本依赖 Pillow、NumPy，应用本身没有这些依赖。机器可读结果位于 `build/weather-calibration/final/audit.json`，负向对照结果位于 `negative-controls.json`。

## 验证边界

上述结果是实际样式源码的离屏渲染与用户参考截图之间的像素检查。原生控件负责实机上的颜色、选中态与布局。此次实时 UI 工具读取系统菜单栏超时，因此没有获得安装后新的同屏截图，不能把离屏通过表述为已经逐像素确认了整个实机菜单栏。后续若有新的同屏截图，应使用该截图重新核对，而不是继续凭目测猜字号。
