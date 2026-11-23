using System.Diagnostics.Eventing.Reader;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 사후 복구(spec 2절 6번): System 이벤트 로그에서 earliestStart~지금 사이의 절전 해제·부팅·로그온 이벤트를 찾는다.
internal static class RecoveryQuery
{
    /// 결과: 가장 이른 이벤트 시각(없으면 earliestStart). 조회 실패·10초 초과면 null.
    public static async Task<DateTime?> RunAsync(RecoveryRequest request)
    {
        try
        {
            var work = Task.Run(() => Query(request));
            var finished = await Task.WhenAny(work, Task.Delay(Recovery.Timeout)).ConfigureAwait(true);
            if (finished != work)
            {
                Log.Write("사후 복구 조회 시간 초과");
                return null;
            }
            return await work.ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            Log.Write($"사후 복구 조회 실패: {ex.Message}");
            return null;
        }
    }

    private static DateTime? Query(RecoveryRequest request)
    {
        try
        {
            // 엔진의 시각은 로컬 벽시계(Kind 없음) — 이벤트 로그 쿼리는 UTC.
            var fromUtc = DateTime.SpecifyKind(request.EarliestStart, DateTimeKind.Local).ToUniversalTime();
            var toUtc = DateTime.SpecifyKind(request.Now, DateTimeKind.Local).ToUniversalTime();
            var xpath = Recovery.BuildXPath(fromUtc, toUtc);

            var events = new List<SystemEvent>();
            var query = new EventLogQuery("System", PathType.LogName, xpath);
            using var reader = new EventLogReader(query);
            for (var record = reader.ReadEvent(); record is not null; record = reader.ReadEvent())
            {
                using (record)
                {
                    var kind = Recovery.Classify(record.ProviderName, record.Id);
                    if (kind is null || record.TimeCreated is not { } created) continue;
                    events.Add(new SystemEvent(DateTime.SpecifyKind(created, DateTimeKind.Unspecified), kind.Value));
                }
            }
            return Recovery.Pick(events, request.EarliestStart, request.Now);
        }
        catch (Exception ex)
        {
            Log.Write($"이벤트 로그 조회 예외: {ex.GetType().Name} {ex.Message}");
            return null;
        }
    }
}
