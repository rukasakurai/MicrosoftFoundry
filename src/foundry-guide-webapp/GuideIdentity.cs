using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

internal static class GuideIdentity
{
    internal static bool TryGetSubject(ClaimsPrincipal user, out string subject)
    {
        var tenantId = user.FindFirstValue("tid");
        var userId = user.FindFirstValue("oid") ?? user.FindFirstValue("sub");
        if (string.IsNullOrWhiteSpace(tenantId) || string.IsNullOrWhiteSpace(userId))
        {
            subject = string.Empty;
            return false;
        }

        subject = Hash($"{tenantId}:{userId}");
        return true;
    }

    internal static string Hash(string value) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
