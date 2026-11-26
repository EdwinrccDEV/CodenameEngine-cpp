#include "EngineNative.h"

#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <string>
#include <vector>

#ifdef _WIN32
	#ifndef NOMINMAX
		#define NOMINMAX
	#endif
	#include <windows.h>
#else
	#include <dirent.h>
	#include <sys/stat.h>
#endif

namespace
{
	/** ::String -> std::string (UTF-8 ya normalizado por hxcpp). */
	std::string toStd(const ::String &value)
	{
		const char *raw = value.c_str();
		return raw == nullptr ? std::string() : std::string(raw);
	}

#ifdef _WIN32
	std::wstring toWide(const std::string &value)
	{
		if (value.empty()) return std::wstring();

		int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), (int)value.size(), nullptr, 0);
		if (size <= 0) return std::wstring();

		std::wstring result((size_t)size, L'\0');
		MultiByteToWideChar(CP_UTF8, 0, value.c_str(), (int)value.size(), &result[0], size);
		return result;
	}

	std::string toUtf8(const std::wstring &value)
	{
		if (value.empty()) return std::string();

		int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), (int)value.size(), nullptr, 0, nullptr, nullptr);
		if (size <= 0) return std::string();

		std::string result((size_t)size, '\0');
		WideCharToMultiByte(CP_UTF8, 0, value.c_str(), (int)value.size(), &result[0], size, nullptr, nullptr);
		return result;
	}

	void collect(const std::string &root, const std::string &relative, bool recursive, std::vector<std::string> &out)
	{
		std::string folder = relative.empty() ? root : root + "/" + relative;

		WIN32_FIND_DATAW data;
		HANDLE handle = FindFirstFileW(toWide(folder + "/*").c_str(), &data);
		if (handle == INVALID_HANDLE_VALUE) return;

		do
		{
			const std::wstring rawName = data.cFileName;
			if (rawName == L"." || rawName == L"..") continue;

			std::string entry = toUtf8(rawName);
			std::string child = relative.empty() ? entry : relative + "/" + entry;

			if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
			{
				if (recursive) collect(root, child, recursive, out);
			}
			else out.push_back(child);
		}
		while (FindNextFileW(handle, &data) != 0);

		FindClose(handle);
	}
#else
	void collect(const std::string &root, const std::string &relative, bool recursive, std::vector<std::string> &out)
	{
		std::string folder = relative.empty() ? root : root + "/" + relative;

		DIR *dir = opendir(folder.c_str());
		if (dir == nullptr) return;

		struct dirent *entry = nullptr;
		while ((entry = readdir(dir)) != nullptr)
		{
			std::string name = entry->d_name;
			if (name == "." || name == "..") continue;

			std::string child = relative.empty() ? name : relative + "/" + name;

			struct stat info;
			if (stat((root + "/" + child).c_str(), &info) != 0) continue;

			if (S_ISDIR(info.st_mode))
			{
				if (recursive) collect(root, child, recursive, out);
			}
			else out.push_back(child);
		}

		closedir(dir);
	}
#endif

	/** Tabla CRC32 (polinomio invertido estandar). */
	const unsigned int *crcTable()
	{
		static unsigned int table[256];
		static bool ready = false;

		if (!ready)
		{
			for (unsigned int i = 0; i < 256; ++i)
			{
				unsigned int value = i;
				for (int bit = 0; bit < 8; ++bit)
					value = (value & 1u) ? (0xEDB88320u ^ (value >> 1)) : (value >> 1);
				table[i] = value;
			}
			ready = true;
		}

		return table;
	}
}

::String EngineNative::version()
{
	return ::String("1.0.0");
}

::Array< ::String> EngineNative::scanDir(::String path, bool recursive)
{
	std::vector<std::string> files;
	collect(toStd(path), std::string(), recursive, files);
	std::sort(files.begin(), files.end());

	::Array< ::String> result = Array_obj< ::String>::__new();
	result->reserve((int)files.size());
	for (size_t i = 0; i < files.size(); ++i)
		result->push(::String(files[i].c_str()));

	return result;
}

int EngineNative::crc32File(::String path)
{
	std::string raw = toStd(path);

#ifdef _WIN32
	FILE *file = _wfopen(toWide(raw).c_str(), L"rb");
#else
	FILE *file = fopen(raw.c_str(), "rb");
#endif
	if (file == nullptr) return -1;

	const unsigned int *table = crcTable();
	unsigned int crc = 0xFFFFFFFFu;
	unsigned char buffer[65536];
	size_t read = 0;

	while ((read = fread(buffer, 1, sizeof(buffer), file)) > 0)
		for (size_t i = 0; i < read; ++i)
			crc = table[(crc ^ buffer[i]) & 0xFFu] ^ (crc >> 8);

	fclose(file);
	return (int)(crc ^ 0xFFFFFFFFu);
}
