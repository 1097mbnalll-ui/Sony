// SPDX-License-Identifier: AGPL-3.0-only
// Host smoke test for the Tarjuman bridge. Runs on Linux/macOS in CI.
// - fake console answers discovery on 127.0.0.1:9302 -> scanner must find it
// - session to a closed port must fail cleanly with a QUIT event
// - registration against nothing must fail cleanly

#include "trjm.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static atomic_int found = 0;
static atomic_int quit_events = 0;
static atomic_int regist_done = 0;
static char found_name[64];

static void log_cb(TrjmLogLevel level, const char *msg, void *user)
{
	(void)user;
	if(level >= TRJM_LOG_INFO)
		fprintf(stderr, "[chiaki %d] %s\n", level, msg);
}

static void host_cb(const TrjmFoundHost *h, void *user)
{
	(void)user;
	snprintf(found_name, sizeof(found_name), "%s", h->name);
	fprintf(stderr, "found host %s name=%s ps5=%d state=%d app=%s\n", h->addr, h->name, h->ps5, h->state, h->running_app_name);
	if(h->ps5 && h->state == TRJM_HOST_STANDBY)
		atomic_store(&found, 1);
}

static void *fake_console(void *arg)
{
	(void)arg;
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	struct sockaddr_in sa = { 0 };
	sa.sin_family = AF_INET;
	sa.sin_port = htons(9302);
	sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if(bind(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0)
	{
		perror("fake console bind");
		return NULL;
	}
	char buf[512];
	struct sockaddr_in from;
	socklen_t fl = sizeof(from);
	ssize_t n = recvfrom(fd, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&from, &fl);
	if(n > 0)
	{
		buf[n] = 0;
		fprintf(stderr, "fake console got: %.*s\n", (int)strcspn(buf, "\n"), buf);
		const char *resp =
			"HTTP/1.1 620 Server Standby\n"
			"host-id:ABCDEF123456\n"
			"host-type:PS5\n"
			"host-name:TestPS5\n"
			"host-request-port:997\n"
			"device-discovery-protocol-version:00030010\n"
			"system-version:07000001\n\n";
		sendto(fd, resp, strlen(resp), 0, (struct sockaddr *)&from, fl);
	}
	close(fd);
	return NULL;
}

static void event_cb(TrjmEventType type, int code, const char *msg, void *user)
{
	(void)user;
	fprintf(stderr, "session event %d code=%d msg=%s\n", type, code, msg ? msg : "");
	if(type == TRJM_EVENT_QUIT)
		atomic_store(&quit_events, 1);
}

static void regist_cb(const TrjmRegistResult *r, void *user)
{
	(void)user;
	fprintf(stderr, "regist finished success=%d canceled=%d\n", r->success, r->canceled);
	atomic_store(&regist_done, r->success ? 2 : 1);
}

#define WAIT_FOR(cond, ms) do { for(int _i = 0; _i < (ms) / 10 && !(cond); _i++) usleep(10000); } while(0)

int main(void)
{
	int fails = 0;
	if(trjm_init(log_cb, NULL) != 0) { fprintf(stderr, "FAIL init\n"); return 1; }

	// 1. discovery
	pthread_t th;
	pthread_create(&th, NULL, fake_console, NULL);
	usleep(100000);
	TrjmScanner *sc = trjm_scanner_new(host_cb, NULL);
	if(!sc) { fprintf(stderr, "FAIL scanner_new\n"); return 1; }
	trjm_scanner_ping(sc, "127.0.0.1");
	WAIT_FOR(atomic_load(&found), 3000);
	if(!atomic_load(&found) || strcmp(found_name, "TestPS5") != 0) { fprintf(stderr, "FAIL discovery\n"); fails++; }
	else fprintf(stderr, "OK discovery\n");
	int swept = trjm_scanner_sweep(sc);
	fprintf(stderr, "OK sweep pinged %d addresses\n", swept);
	trjm_scanner_free(sc);
	pthread_join(th, NULL);

	// 2. wakeup with a valid-format key must not crash
	char key[16] = { 0 };
	memcpy(key, "1a2b3c4d", 8);
	fprintf(stderr, "wakeup -> %d\n", trjm_wakeup("127.0.0.1", key, true));

	// 3. session to closed port fails cleanly
	TrjmSessionConfig cfg;
	memset(&cfg, 0, sizeof(cfg));
	cfg.host = "127.0.0.1";
	cfg.ps5 = true;
	memcpy(cfg.regist_key, key, 16);
	cfg.resolution = 720;
	cfg.fps = 30;
	cfg.codec = TRJM_CODEC_H264;
	cfg.enable_audio = true;
	TrjmSessionCallbacks cbs;
	memset(&cbs, 0, sizeof(cbs));
	cbs.event = event_cb;
	int err = -1;
	TrjmSession *s = trjm_session_start(&cfg, &cbs, &err);
	if(!s) { fprintf(stderr, "FAIL session_start err=%d %s\n", err, trjm_error_string(err)); fails++; }
	else
	{
		TrjmControllerInput in;
		memset(&in, 0, sizeof(in));
		in.buttons = TRJM_BTN_CROSS | TRJM_BTN_PS;
		in.r2 = 255;
		in.left_y = -32768;
		in.touch_active[0] = true;
		in.touch_x[0] = 5000; // clamped
		in.touch_y[0] = 100;
		fprintf(stderr, "set_input -> %d\n", trjm_session_set_input(s, &in));
		in.touch_active[0] = false;
		trjm_session_set_input(s, &in);
		WAIT_FOR(atomic_load(&quit_events), 15000);
		if(!atomic_load(&quit_events)) { fprintf(stderr, "FAIL no quit event\n"); fails++; }
		else fprintf(stderr, "OK session quit cleanly\n");
		trjm_session_free(s);
	}

	// 4. registration against nothing fails cleanly
	uint8_t acc[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
	TrjmRegist *r = trjm_regist_start("127.0.0.1", true, acc, 12345678, regist_cb, NULL);
	if(!r) { fprintf(stderr, "FAIL regist_start\n"); fails++; }
	else
	{
		WAIT_FOR(atomic_load(&regist_done), 20000);
		fprintf(stderr, "regist result=%d\n", atomic_load(&regist_done));
		trjm_regist_free(r);
		if(atomic_load(&regist_done) != 1) { fprintf(stderr, "FAIL regist did not fail cleanly\n"); fails++; }
		else fprintf(stderr, "OK regist failed cleanly\n");
	}

	fprintf(stderr, fails ? "SMOKE FAILED (%d)\n" : "SMOKE PASSED\n", fails);
	return fails ? 1 : 0;
}
