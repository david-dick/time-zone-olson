/* 
 *
 * Compile on Fedora
 *
 * sudo dnf install mono-core
 * mcs date.cs
 *
 */

using System;
using System.Globalization;

class Program {
	static void Main(string[] args) {
		DateTime timeUtc = DateTime.ParseExact(args[0], "yyyy/MM/dd HH:mm:ss", CultureInfo.InvariantCulture);
		TimeZoneInfo zone = TimeZoneInfo.FindSystemTimeZoneById(args[1]);
		DateTime time = TimeZoneInfo.ConvertTimeFromUtc(timeUtc, zone);
		string zoneName = zone.IsDaylightSavingTime(time) ?  zone.DaylightName : zone.StandardName;
		Console.WriteLine("{0} {1}", time.ToString("yyyy/MM/dd HH:mm:ss"), zoneName);
	}
}

