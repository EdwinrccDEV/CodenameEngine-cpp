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
	return ::String("1.1.1");
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

/** Lee una muestra little endian de tamano variable. */
static int readSample(const unsigned char *data, int pos, int bytesPerSample)
{
	switch (bytesPerSample)
	{
		case 1:
			return (int)(signed char)data[pos];
		case 2:
			return (int)(short)((unsigned short)data[pos] | ((unsigned short)data[pos + 1] << 8));
		case 3:
		{
			int value = (int)((unsigned int)data[pos] | ((unsigned int)data[pos + 1] << 8) | ((unsigned int)data[pos + 2] << 16));
			if ((value & 0x800000) != 0) value -= 0x1000000;
			return value;
		}
		default:
			return (int)((unsigned int)data[pos] | ((unsigned int)data[pos + 1] << 8) | ((unsigned int)data[pos + 2] << 16)
				| ((unsigned int)data[pos + 3] << 24));
	}
}

::Array<Float> EngineNative::audioAmplitudes(::Array<unsigned char> pcm, int bitsPerSample, int channels,
	::Array<int> startFrames, ::Array<int> endFrames)
{
	const int count = startFrames == nullptr ? 0 : startFrames->length;
	::Array<Float> result = Array_obj<Float>::__new();
	result->reserve(count);

	const int bytesPerSample = bitsPerSample >> 3;
	const int frameSize = bytesPerSample * channels;
	const bool valid = pcm != nullptr && bitsPerSample > 0 && (bitsPerSample & 7) == 0
		&& channels > 0 && endFrames != nullptr && endFrames->length >= count;

	const unsigned char *data = valid ? (const unsigned char *)pcm->getBase() : nullptr;
	const int pcmLength = valid ? (int)pcm->length : 0;
	// Cast sin signo para que 32 bits de 2147483648 y no un negativo.
	const double scale = valid ? 1.0 / (double)((unsigned int)1 << (bitsPerSample - 1)) : 0.0;

	for (int i = 0; i < count; ++i)
	{
		if (!valid)
		{
			result->push(0.0);
			continue;
		}

		// Los indices son frames: se convierten a bytes de PCM.
		const int start = (int)startFrames->__get(i) * frameSize;
		int end = (int)endFrames->__get(i) * frameSize;
		if (end > pcmLength) end = pcmLength;

		// Pico absoluto de la ventana. (max - min) daba el doble del pico real, asi
		// que casi cualquier master quedaba clampeado a 1 y la waveform salia plana.
		// long long para no desbordar con muestras de 32 bits.
		long long peak = 0;
		int pos = start;

		while (pos + bytesPerSample <= end)
		{
			const int value = readSample(data, pos, bytesPerSample);
			const long long magnitude = value < 0 ? -(long long)value : (long long)value;
			if (magnitude > peak) peak = magnitude;

			pos += frameSize;
		}

		result->push((Float)(peak * scale));
	}

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
