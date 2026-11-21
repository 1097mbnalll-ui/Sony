// SPDX-License-Identifier: AGPL-3.0-only
//
// Tarjuman bridge: a small, Swift-friendly C API on top of chiaki-ng.
// All callbacks are invoked on chiaki's internal threads; the Swift side is
// responsible for hopping to the main thread when touching UI.

#ifndef TRJM_H
#define TRJM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TRJM_REGIST_KEY_SIZE 16
#define TRJM_MORNING_SIZE 16
#define TRJM_ACCOUNT_ID_SIZE 8

typedef enum {
	TRJM_LOG_DEBUG = 0,
	TRJM_LOG_INFO = 1,
	TRJM_LOG_WARNING = 2,
	TRJM_LOG_ERROR = 3
} TrjmLogLevel;

typedef void (*TrjmLogCb)(TrjmLogLevel level, const char *msg, void *user);

/** Must be called once before anything else. Returns 0 on success. */
int trjm_init(TrjmLogCb log_cb, void *log_user);

const char *trjm_error_string(int err);

// ---------------------------------------------------------------- discovery

typedef enum {
	TRJM_HOST_UNKNOWN = 0,
	TRJM_HOST_READY = 1,
	TRJM_HOST_STANDBY = 2
} TrjmHostState;

typedef struct {
	char addr[64];
	char name[64];
	char host_id[64];
	char host_type[32];
	char system_version[32];
	char running_app_name[128];
	char running_app_titleid[32];
	TrjmHostState state;
	bool ps5;
} TrjmFoundHost;

typedef void (*TrjmHostCb)(const TrjmFoundHost *host, void *user);

typedef struct TrjmScanner TrjmScanner;

/** Opens a UDP socket and starts listening for discovery replies. */
TrjmScanner *trjm_scanner_new(TrjmHostCb cb, void *user);
/** Sends one search packet (PS4 + PS5 ports) to an IPv4 address. */
int trjm_scanner_ping(TrjmScanner *scanner, const char *ipv4);
/**
 * Sends search packets by unicast to every address of the local IPv4
 * subnets (Wi-Fi / Ethernet). Does not need the iOS multicast entitlement.
 * Returns the number of addresses pinged.
 */
int trjm_scanner_sweep(TrjmScanner *scanner);
void trjm_scanner_free(TrjmScanner *scanner);

/** Wakes a registered console from rest mode. */
int trjm_wakeup(const char *host, const char regist_key[TRJM_REGIST_KEY_SIZE], bool ps5);

// ------------------------------------------------------------- registration

typedef struct {
	bool success;
	bool canceled;
	char server_nickname[33];
	uint8_t server_mac[6];
	char regist_key[TRJM_REGIST_KEY_SIZE];
	uint8_t morning[TRJM_MORNING_SIZE];
	uint32_t console_pin;
} TrjmRegistResult;

typedef void (*TrjmRegistCb)(const TrjmRegistResult *result, void *user);

typedef struct TrjmRegist TrjmRegist;

TrjmRegist *trjm_regist_start(const char *host, bool ps5, const uint8_t account_id[TRJM_ACCOUNT_ID_SIZE],
		uint32_t pin, TrjmRegistCb cb, void *user);
/** Stops (if still running) and frees. Never call from inside the callback. */
void trjm_regist_free(TrjmRegist *regist);

// ------------------------------------------------------------------ session

typedef enum {
	TRJM_EVENT_CONNECTED = 0,
	TRJM_EVENT_LOGIN_PIN_REQUEST = 1,
	TRJM_EVENT_QUIT = 2,
	TRJM_EVENT_NICKNAME = 3
} TrjmEventType;

/** Quit codes delivered with TRJM_EVENT_QUIT (0 = normal end). */
#define TRJM_QUIT_REQUEST_UNKNOWN 2
#define TRJM_QUIT_CONNECTION_REFUSED 3
#define TRJM_QUIT_RP_IN_USE 4
#define TRJM_QUIT_RP_CRASH 5
#define TRJM_QUIT_VERSION_MISMATCH 6
#define TRJM_QUIT_CTRL_UNKNOWN 7
#define TRJM_QUIT_CTRL_CONNECT_FAILED 8
#define TRJM_QUIT_CTRL_CONNECTION_REFUSED 9
#define TRJM_QUIT_STREAM_UNKNOWN 10
#define TRJM_QUIT_REMOTE_DISCONNECTED 11

typedef enum {
	TRJM_CODEC_H264 = 0,
	TRJM_CODEC_H265 = 1
} TrjmCodec;

typedef struct {
	const char *host;
	bool ps5;
	char regist_key[TRJM_REGIST_KEY_SIZE];
	uint8_t morning[TRJM_MORNING_SIZE];
	uint8_t account_id[TRJM_ACCOUNT_ID_SIZE];
	int resolution; // 360, 540, 720, 1080
	int fps;        // 30, 60
	TrjmCodec codec;
	bool enable_audio;
} TrjmSessionConfig;

typedef struct {
	/** type, error/quit code, optional message (may be NULL). */
	void (*event)(TrjmEventType type, int code, const char *msg, void *user);
	/** Annex-B access unit. Return false to request a new keyframe. */
	bool (*video)(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered, void *user);
	void (*audio_format)(uint32_t channels, uint32_t rate, void *user);
	/** Interleaved signed 16-bit PCM; frames = samples per channel. */
	void (*audio_pcm)(const int16_t *buf, size_t frames, void *user);
	void *user;
} TrjmSessionCallbacks;

typedef struct TrjmSession TrjmSession;

TrjmSession *trjm_session_start(const TrjmSessionConfig *config, const TrjmSessionCallbacks *callbacks, int *err_out);
int trjm_session_request_keyframe(TrjmSession *session);
int trjm_session_set_login_pin(TrjmSession *session, const char *pin);
/** Stops, joins and frees. Never call from inside a callback. */
void trjm_session_free(TrjmSession *session);

#ifdef __cplusplus
}
#endif

#endif // TRJM_H
