// Validates the packages Bref wrote against the Open XML SDK, the reference
// for what Office opens without offering a repair. An original file may
// already break the schema; a rewrite fails only on errors it adds.
//
//   dotnet run -- <originals> <rewritten>

using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

if (args.Length != 2)
{
    Console.Error.WriteLine("usage: validate <originals> <rewritten>");
    return 2;
}

var validator = new OpenXmlValidator(FileFormatVersions.Microsoft365);
// Documents Bref edited may lose parts, a deleted slide; the parts it added
// must be valid.
var edited = Environment.GetEnvironmentVariable("BREF_EDITED") == "1";
int files = 0, skipped = 0, failed = 0;
foreach (var rewritten in Directory.EnumerateFiles(args[1], "*", SearchOption.AllDirectories).Order())
{
    var name = Path.GetRelativePath(args[1], rewritten);
    var before = Check(Path.Combine(args[0], name));
    if (before == null)
    {
        skipped++;
        continue;
    }
    files++;
    var after = Check(rewritten);
    var added = after == null
        ? ["the rewritten package does not open"]
        : before.Parts.Except(after.Parts).Where(_ => !edited).Select(p => $"{p} lost")
            // parts the SDK could not see in the original, under a name
            // Bref normalized, bring their own errors
            .Concat(after.Errors.Where(e => before.Parts.Contains(e.Part) && !before.Errors.Contains(e)).Select(e => e.Text))
            .Concat(after.Errors.Where(e => edited && !before.Parts.Contains(e.Part)).Select(e => e.Text))
            .ToList();
    if (added.Count > 0)
    {
        failed++;
        Console.WriteLine($"{name}: {added.Count} new errors");
        foreach (var e in added.Take(10))
            Console.WriteLine($"  {e}");
    }
}
Console.WriteLine($"{files} validated, {failed} with new errors, {skipped} skipped (the original does not open)");
return failed > 0 ? 1 : 0;

// Check lists the parts of a package and its validation errors, null when
// the SDK cannot open it at all.
Report? Check(string path)
{
    OpenXmlPackage? doc;
    try
    {
        doc = Open(path);
    }
    catch (Exception)
    {
        return null;
    }
    if (doc == null)
        return null;
    using (doc)
    {
        HashSet<string> parts = [""];
        HashSet<Error> errors;
        try
        {
            parts.UnionWith(doc.GetAllParts().Select(p => p.Uri.ToString()));
            errors = validator.Validate(doc)
                .Select(e => new Error(e.Part?.Uri.ToString() ?? "", $"{e.Part?.Uri} {e.Path?.XPath} {e.Id}: {e.Description}"))
                .ToHashSet();
        }
        catch (Exception e)
        {
            errors = [new Error("", $"validation stopped: {e.GetType().Name}: {e.Message}")];
        }
        return new Report(parts, errors);
    }
}

static OpenXmlPackage? Open(string path) => Path.GetExtension(path).ToLowerInvariant() switch
{
    ".docx" or ".docm" or ".dotx" or ".dotm" => WordprocessingDocument.Open(path, false),
    ".xlsx" or ".xlsm" or ".xltx" or ".xltm" => SpreadsheetDocument.Open(path, false),
    ".pptx" or ".pptm" or ".potx" or ".potm" or ".ppsx" or ".ppsm" => PresentationDocument.Open(path, false),
    _ => null,
};

record Error(string Part, string Text);

// Parts holds "" for the package itself.
record Report(HashSet<string> Parts, HashSet<Error> Errors);
