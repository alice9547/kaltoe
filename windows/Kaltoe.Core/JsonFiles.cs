// 파일 모델(settings.json, clockin.json)과 직렬화. 읽기 실패·검증 실패는 기본값으로.
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Kaltoe.Core;

internal sealed class HhmmConverter : JsonConverter<TimeOnly>
{
    public override TimeOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString();
        if (!TimeText.TryParse(text, out var value)) throw new JsonException($"잘못된 시각: {text}");
        return value;
    }

    public override void Write(Utf8JsonWriter writer, TimeOnly value, JsonSerializerOptions options)
        => writer.WriteStringValue(TimeText.Format(value));
}

public static class KaltoeJson
{
    public static readonly JsonSerializerOptions Options = Create();

    private static JsonSerializerOptions Create()
    {
        var o = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };
        o.Converters.Add(new HhmmConverter());
        o.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return o;
    }
}

/// 위젯 위치(물리 픽셀)·표시 여부. 값이 null 이면 기본 위치. 모양마다 자기 위치를 가진다.
/// 터미널은 창의 왼쪽 위(X, Y), 말풍선은 창의 오른쪽 아래(BubbleRight, BubbleBottom) —
/// 말풍선은 문구 길이에 따라 창 폭이 바뀌는데, 마스코트(오른쪽 아래)는 제자리에 있어야 하기 때문.
public sealed record WidgetState
{
    public int? X { get; init; }
    public int? Y { get; init; }
    public int? BubbleRight { get; init; }
    public int? BubbleBottom { get; init; }
    public bool Visible { get; init; } = true;
}

/// settings.json 전체.
public sealed record AppFile
{
    public AppSettings Settings { get; init; } = new();
    public WidgetState Widget { get; init; } = new();
    /// 첫 실행 때 로그인 시 자동 실행을 켰는지.
    public bool LaunchAtLoginInitialized { get; init; }

    /// 깨졌거나 검증에 실패하면 기본값(위젯 상태는 가능한 한 유지).
    public static AppFile Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new AppFile();
        try
        {
            var file = JsonSerializer.Deserialize<AppFile>(json, KaltoeJson.Options);
            if (file is null) return new AppFile();
            file = file with { Settings = file.Settings ?? new AppSettings(), Widget = file.Widget ?? new WidgetState() };
            if (file.Settings.Flexible is null || file.Settings.Fixed is null || file.Settings.Lunch is null
                || file.Settings.Notify is null || file.Settings.Widget is null
                || SettingsValidator.Validate(file.Settings) is not null)
                return file with { Settings = new AppSettings() };
            return file;
        }
        catch (Exception)
        {
            return new AppFile();
        }
    }

    public string ToJson() => JsonSerializer.Serialize(this, KaltoeJson.Options);
}
