// SPDX-License-Identifier: AGPL-3.0-only

#include "trjm.h"

#include <chiaki/common.h>
#include <chiaki/log.h>
#include <chiaki/discovery.h>
#include <chiaki/regist.h>
#include <chiaki/session.h>
#include <chiaki/opusdecoder.h>
#include <chiaki/controller.h>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

_Static_assert(TRJM_QUIT_CONNECTION_REFUSED == CHIAKI_QUIT_REASON_SESSION_REQUEST_CONNECTION_REFUSED, "quit codes");
_Static_assert(TRJM_QUIT_RP_IN_USE == CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE, "quit codes");
_Static_assert(TRJM_QUIT_VERSION_MISMATCH == CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_VERSION_MISMATCH, "quit codes");
_Static_assert(TRJM_QUIT_CTRL_CONNECTION_REFUSED == CHIAKI_QUIT_REASON_CTRL_CONNECTION_REFUSED, "quit codes");
_Static_assert(TRJM_QUIT_REMOTE_DISCONNECTED == CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_DISCONNECTED, "quit codes");

// ------------------------------------------------------------------ logging

static TrjmLogCb g_log_cb = NULL;
static void *g_log_user = NULL;
static ChiakiLog g_log;

static void log_forward(ChiakiLogLevel level, const char *msg, void *user)
{
	(void)user;
	if(!g_log_cb)
		return;
	TrjmLogLevel l = TRJM_LOG_DEBUG;
	switch(level)
	{
		case CHIAKI_LOG_ERROR: l = TRJM_LOG_ERROR; break;
		case CHIAKI_LOG_WARNING: l = TRJM_LOG_WARNING; break;
		case CHIAKI_LOG_INFO: l = TRJM_LOG_INFO; break;
		default: l = TRJM_LOG_DEBUG; break;
	}
	g_log_cb(l, msg, g_log_user);
}

int trjm_init(TrjmLogCb log_cb, void *log_user)
{
	g_log_cb = log_cb;
	g_log_user = log_user;
	chiaki_log_init(&g_log, CHIAKI_LOG_ALL & ~CHIAKI_LOG_VERBOSE, log_forward, NULL);
	return (int)chiaki_lib_init();
}

const char *trjm_error_string(int err)
{
	return chiaki_error_string((ChiakiErrorCode)err);
}

static void copy_str(char *dst, size_t dst_size, const char *src)
{
	if(!dst_size)
		return;
	if(!src)
	{
		dst[0] = '\0';
		return;
	}
	snprintf(dst, dst_size, "%s", src);
}

// ---------------------------------------------------------------- discovery

struct TrjmScanner
{
	ChiakiDiscovery discovery;
	ChiakiDiscoveryThread thread;
	TrjmHostCb cb;
	void *user;
};

static void scanner_host_cb(ChiakiDiscoveryHost *host, void *user)
{
	TrjmScanner *scanner = user;
	if(!scanner->cb || !host)
		return;
	TrjmFoundHost out;
	memset(&out, 0, sizeof(out));
	copy_str(out.addr, sizeof(out.addr), host->host_addr);
	copy_str(out.name, sizeof(out.name), host->host_name);
	copy_str(out.host_id, sizeof(out.host_id), host->host_id);
	copy_str(out.host_type, sizeof(out.host_type), host->host_type);
	copy_str(out.system_version, sizeof(out.system_version), host->system_version);
	copy_str(out.running_app_name, sizeof(out.running_app_name), host->running_app_name);
	copy_str(out.running_app_titleid, sizeof(out.running_app_titleid), host->running_app_titleid);
	switch(host->state)
	{
		case CHIAKI_DISCOVERY_HOST_STATE_READY: out.state = TRJM_HOST_READY; break;
		case CHIAKI_DISCOVERY_HOST_STATE_STANDBY: out.state = TRJM_HOST_STANDBY; break;
		default: out.state = TRJM_HOST_UNKNOWN; break;
	}
	out.ps5 = chiaki_discovery_host_is_ps5(host);
	scanner->cb(&out, scanner->user);
}

TrjmScanner *trjm_scanner_new(TrjmHostCb cb, void *user)
{
	TrjmScanner *scanner = calloc(1, sizeof(TrjmScanner));
	if(!scanner)
		return NULL;
	scanner->cb = cb;
	scanner->user = user;
	if(chiaki_discovery_init(&scanner->discovery, &g_log, AF_INET) != CHIAKI_ERR_SUCCESS)
	{
		free(scanner);
		return NULL;
	}
	if(chiaki_discovery_thread_start(&scanner->thread, &scanner->discovery, scanner_host_cb, scanner) != CHIAKI_ERR_SUCCESS)
	{
		chiaki_discovery_fini(&scanner->discovery);
		free(scanner);
		return NULL;
	}
	return scanner;
}

static int scanner_ping_addr(TrjmScanner *scanner, struct in_addr addr)
{
	struct sockaddr_in sa;
	memset(&sa, 0, sizeof(sa));
	sa.sin_family = AF_INET;
	sa.sin_addr = addr;

	ChiakiDiscoveryPacket packet;
	memset(&packet, 0, sizeof(packet));
	packet.cmd = CHIAKI_DISCOVERY_CMD_SRCH;

	packet.protocol_version = CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5;
	sa.sin_port = htons(CHIAKI_DISCOVERY_PORT_PS5);
	ChiakiErrorCode err = chiaki_discovery_send(&scanner->discovery, &packet, (struct sockaddr *)&sa, sizeof(sa));

	packet.protocol_version = CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS4;
	sa.sin_port = htons(CHIAKI_DISCOVERY_PORT_PS4);
	chiaki_discovery_send(&scanner->discovery, &packet, (struct sockaddr *)&sa, sizeof(sa));
	return (int)err;
}

int trjm_scanner_ping(TrjmScanner *scanner, const char *ipv4)
{
	if(!scanner || !ipv4)
		return CHIAKI_ERR_INVALID_DATA;
	struct in_addr addr;
	if(inet_pton(AF_INET, ipv4, &addr) != 1)
		return CHIAKI_ERR_INVALID_DATA;
	return scanner_ping_addr(scanner, addr);
}

int trjm_scanner_sweep(TrjmScanner *scanner)
{
	if(!scanner)
		return 0;
	struct ifaddrs *ifs = NULL;
	if(getifaddrs(&ifs) != 0)
		return 0;
	int count = 0;
	for(struct ifaddrs *i = ifs; i; i = i->ifa_next)
	{
		if(!i->ifa_addr || !i->ifa_netmask || i->ifa_addr->sa_family != AF_INET)
			continue;
		if((i->ifa_flags & IFF_LOOPBACK) || !(i->ifa_flags & IFF_UP))
			continue;
		// Wi-Fi/Ethernet only; skip cellular (pdp_ip*), VPN tunnels (utun*) etc.
		if(strncmp(i->ifa_name, "en", 2) != 0 && strncmp(i->ifa_name, "eth", 3) != 0 && strncmp(i->ifa_name, "wl", 2) != 0)
			continue;
		uint32_t ip = ntohl(((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr);
		uint32_t mask = ntohl(((struct sockaddr_in *)i->ifa_netmask)->sin_addr.s_addr);
		// Limit very large subnets to the /22 around our own address.
		if(mask < 0xfffffc00u)
			mask = 0xfffffc00u;
		uint32_t net = ip & mask;
		uint32_t bcast = net | ~mask;
		for(uint32_t a = net + 1; a < bcast; a++)
		{
			if(a == ip)
				continue;
			struct in_addr addr;
			addr.s_addr = htonl(a);
			scanner_ping_addr(scanner, addr);
			count++;
		}
	}
	freeifaddrs(ifs);
	return count;
}

void trjm_scanner_free(TrjmScanner *scanner)
{
	if(!scanner)
		return;
	chiaki_discovery_thread_stop(&scanner->thread);
	chiaki_discovery_fini(&scanner->discovery);
	free(scanner);
}

int trjm_wakeup(const char *host, const char regist_key[TRJM_REGIST_KEY_SIZE], bool ps5)
{
	char key[TRJM_REGIST_KEY_SIZE + 1];
	memcpy(key, regist_key, TRJM_REGIST_KEY_SIZE);
	key[TRJM_REGIST_KEY_SIZE] = '\0';
	// regist key is a zero-padded hex string; credential is its value.
	size_t len = strlen(key);
	if(len == 0 || len > 8)
		return CHIAKI_ERR_INVALID_DATA;
	char *end = NULL;
	unsigned long long credential = strtoull(key, &end, 16);
	if(!end || *end != '\0')
		return CHIAKI_ERR_INVALID_DATA;
	return (int)chiaki_discovery_wakeup(&g_log, NULL, host, (uint64_t)credential, ps5);
}

// ------------------------------------------------------------- registration

struct TrjmRegist
{
	ChiakiRegist regist;
	char *host;
	TrjmRegistCb cb;
	void *user;
};

static void regist_cb(ChiakiRegistEvent *event, void *user)
{
	TrjmRegist *r = user;
	TrjmRegistResult res;
	memset(&res, 0, sizeof(res));
	res.canceled = event->type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_CANCELED;
	res.success = event->type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS && event->registered_host;
	if(res.success)
	{
		ChiakiRegisteredHost *h = event->registered_host;
		memcpy(res.server_nickname, h->server_nickname, sizeof(h->server_nickname));
		res.server_nickname[sizeof(res.server_nickname) - 1] = '\0';
		memcpy(res.server_mac, h->server_mac, sizeof(res.server_mac));
		memcpy(res.regist_key, h->rp_regist_key, sizeof(res.regist_key));
		memcpy(res.morning, h->rp_key, sizeof(res.morning));
		res.console_pin = h->console_pin;
	}
	if(r->cb)
		r->cb(&res, r->user);
}

TrjmRegist *trjm_regist_start(const char *host, bool ps5, const uint8_t account_id[TRJM_ACCOUNT_ID_SIZE],
		uint32_t pin, TrjmRegistCb cb, void *user)
{
	if(!host || !account_id)
		return NULL;
	TrjmRegist *r = calloc(1, sizeof(TrjmRegist));
	if(!r)
		return NULL;
	r->host = strdup(host);
	r->cb = cb;
	r->user = user;

	ChiakiRegistInfo info;
	memset(&info, 0, sizeof(info));
	info.target = ps5 ? CHIAKI_TARGET_PS5_1 : CHIAKI_TARGET_PS4_10;
	info.host = r->host;
	info.broadcast = false; // unicast: no multicast entitlement needed on iOS
	info.psn_online_id = NULL;
	memcpy(info.psn_account_id, account_id, TRJM_ACCOUNT_ID_SIZE);
	info.pin = pin;
	info.console_pin = 0;
	info.holepunch_info = NULL;
	info.rudp = NULL;

	if(chiaki_regist_start(&r->regist, &g_log, &info, regist_cb, r) != CHIAKI_ERR_SUCCESS)
	{
		free(r->host);
		free(r);
		return NULL;
	}
	return r;
}

void trjm_regist_free(TrjmRegist *r)
{
	if(!r)
		return;
	chiaki_regist_stop(&r->regist);
	chiaki_regist_fini(&r->regist);
	free(r->host);
	free(r);
}

// ------------------------------------------------------------------ session

struct TrjmSession
{
	ChiakiSession session;
	ChiakiOpusDecoder opus;
	bool opus_active;
	char *host;
	TrjmSessionCallbacks cb;
};

static void session_event_cb(ChiakiEvent *event, void *user)
{
	TrjmSession *s = user;
	if(!s->cb.event)
		return;
	switch(event->type)
	{
		case CHIAKI_EVENT_CONNECTED:
			s->cb.event(TRJM_EVENT_CONNECTED, 0, NULL, s->cb.user);
			break;
		case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
			s->cb.event(TRJM_EVENT_LOGIN_PIN_REQUEST, event->login_pin_request.pin_incorrect ? 1 : 0, NULL, s->cb.user);
			break;
		case CHIAKI_EVENT_NICKNAME_RECEIVED:
		{
			char nick[sizeof(event->server_nickname) + 1];
			memcpy(nick, event->server_nickname, sizeof(event->server_nickname));
			nick[sizeof(event->server_nickname)] = '\0';
			s->cb.event(TRJM_EVENT_NICKNAME, 0, nick, s->cb.user);
			break;
		}
		case CHIAKI_EVENT_QUIT:
		{
			const char *msg = event->quit.reason_str ? event->quit.reason_str : chiaki_quit_reason_string(event->quit.reason);
			int code = chiaki_quit_reason_is_error(event->quit.reason) ? (int)event->quit.reason : 0;
			s->cb.event(TRJM_EVENT_QUIT, code, msg, s->cb.user);
			break;
		}
		default:
			// Rumble, trigger effects, LEDs etc. are irrelevant: we never act as a controller.
			break;
	}
}

static bool session_video_cb(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)
{
	TrjmSession *s = user;
	if(!s->cb.video)
		return true;
	return s->cb.video(buf, buf_size, frames_lost, frame_recovered, s->cb.user);
}

static void opus_settings_cb(uint32_t channels, uint32_t rate, void *user)
{
	TrjmSession *s = user;
	if(s->cb.audio_format)
		s->cb.audio_format(channels, rate, s->cb.user);
}

static void opus_frame_cb(int16_t *buf, size_t samples_count, void *user)
{
	TrjmSession *s = user;
	if(s->cb.audio_pcm)
		s->cb.audio_pcm(buf, samples_count, s->cb.user);
}

static ChiakiVideoResolutionPreset resolution_preset(int res)
{
	switch(res)
	{
		case 360: return CHIAKI_VIDEO_RESOLUTION_PRESET_360p;
		case 540: return CHIAKI_VIDEO_RESOLUTION_PRESET_540p;
		case 1080: return CHIAKI_VIDEO_RESOLUTION_PRESET_1080p;
		default: return CHIAKI_VIDEO_RESOLUTION_PRESET_720p;
	}
}

TrjmSession *trjm_session_start(const TrjmSessionConfig *config, const TrjmSessionCallbacks *callbacks, int *err_out)
{
	ChiakiErrorCode err = CHIAKI_ERR_INVALID_DATA;
	TrjmSession *s = NULL;
	if(!config || !config->host)
		goto fail;

	err = CHIAKI_ERR_MEMORY;
	s = calloc(1, sizeof(TrjmSession));
	if(!s)
		goto fail;
	if(callbacks)
		s->cb = *callbacks;
	s->host = strdup(config->host);
	if(!s->host)
		goto fail;

	ChiakiConnectInfo info;
	memset(&info, 0, sizeof(info));
	info.ps5 = config->ps5;
	info.host = s->host;
	memcpy(info.regist_key, config->regist_key, sizeof(info.regist_key));
	memcpy(info.morning, config->morning, sizeof(info.morning));
	memcpy(info.psn_account_id, config->account_id, sizeof(info.psn_account_id));
	chiaki_connect_video_profile_preset(&info.video_profile, resolution_preset(config->resolution),
			config->fps >= 60 ? CHIAKI_VIDEO_FPS_PRESET_60 : CHIAKI_VIDEO_FPS_PRESET_30);
	info.video_profile.codec = (config->ps5 && config->codec == TRJM_CODEC_H265) ? CHIAKI_CODEC_H265 : CHIAKI_CODEC_H264;
	info.video_profile_auto_downgrade = true;
	info.enable_keyboard = false;
	info.enable_dualsense = false;
	info.audio_video_disabled = config->enable_audio ? CHIAKI_NONE_DISABLED : CHIAKI_AUDIO_DISABLED;
	info.auto_regist = false;
	info.holepunch_session = NULL;
	info.rudp_sock = NULL;
	info.packet_loss_max = 0.05;
	info.enable_idr_on_fec_failure = true;

	err = chiaki_session_init(&s->session, &info, &g_log);
	if(err != CHIAKI_ERR_SUCCESS)
		goto fail;

	chiaki_session_set_event_cb(&s->session, session_event_cb, s);
	chiaki_session_set_video_sample_cb(&s->session, session_video_cb, s);

	if(config->enable_audio)
	{
		chiaki_opus_decoder_init(&s->opus, &g_log);
		chiaki_opus_decoder_set_cb(&s->opus, opus_settings_cb, opus_frame_cb, s);
		ChiakiAudioSink sink;
		chiaki_opus_decoder_get_sink(&s->opus, &sink);
		chiaki_session_set_audio_sink(&s->session, &sink);
		s->opus_active = true;
	}

	// Tarjuman is a viewer: the controller state stays idle forever.
	ChiakiControllerState idle;
	chiaki_controller_state_set_idle(&idle);
	chiaki_session_set_controller_state(&s->session, &idle);

	err = chiaki_session_start(&s->session);
	if(err != CHIAKI_ERR_SUCCESS)
	{
		chiaki_session_fini(&s->session);
		if(s->opus_active)
			chiaki_opus_decoder_fini(&s->opus);
		goto fail;
	}
	if(err_out)
		*err_out = 0;
	return s;

fail:
	if(s)
	{
		free(s->host);
		free(s);
	}
	if(err_out)
		*err_out = (int)err;
	return NULL;
}

int trjm_session_request_keyframe(TrjmSession *s)
{
	if(!s)
		return CHIAKI_ERR_INVALID_DATA;
	return (int)chiaki_session_request_idr(&s->session);
}

int trjm_session_set_login_pin(TrjmSession *s, const char *pin)
{
	if(!s || !pin)
		return CHIAKI_ERR_INVALID_DATA;
	return (int)chiaki_session_set_login_pin(&s->session, (const uint8_t *)pin, strlen(pin));
}

void trjm_session_free(TrjmSession *s)
{
	if(!s)
		return;
	chiaki_session_stop(&s->session);
	chiaki_session_join(&s->session);
	chiaki_session_fini(&s->session);
	if(s->opus_active)
		chiaki_opus_decoder_fini(&s->opus);
	free(s->host);
	free(s);
}
