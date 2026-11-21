// SPDX-License-Identifier: AGPL-3.0-only
//
// LAN-only build of chiaki-ng: Remote Play over the internet (PSN hole
// punching, AIA certificate fetching) is intentionally left out because it
// pulls in libcurl, libevent, json-c and miniupnpc. These stubs satisfy the
// symbols that the core session code references. holepunch_session is always
// NULL in this build, so none of them are reached at runtime.

#include <netinet/in.h>
#include <arpa/inet.h>
#include <chiaki/common.h>
#include <chiaki/remote/holepunch.h>
#include <string.h>

ChiakiErrorCode chiaki_aia_init(void) { return CHIAKI_ERR_SUCCESS; }
void chiaki_aia_fini(void) {}

CHIAKI_EXPORT void chiaki_holepunch_session_fini(ChiakiHolepunchSession session) { (void)session; }

CHIAKI_EXPORT ChiakiErrorCode chiaki_holepunch_session_punch_hole(ChiakiHolepunchSession session, ChiakiHolepunchPortType port_type)
{
	(void)session; (void)port_type;
	return CHIAKI_ERR_UNKNOWN;
}

CHIAKI_EXPORT uint16_t chiaki_get_ps_ctrl_port(ChiakiHolepunchSession session) { (void)session; return 0; }

CHIAKI_EXPORT void chiaki_get_ps_selected_addr(ChiakiHolepunchSession session, char *ps_ip)
{
	(void)session;
	if(ps_ip) ps_ip[0] = '\0';
}

CHIAKI_EXPORT ChiakiHolepunchRegistInfo chiaki_get_regist_info(ChiakiHolepunchSession session)
{
	(void)session;
	ChiakiHolepunchRegistInfo info;
	memset(&info, 0, sizeof(info));
	return info;
}

CHIAKI_EXPORT chiaki_socket_t *chiaki_get_holepunch_sock(ChiakiHolepunchSession session, ChiakiHolepunchPortType type)
{
	(void)session; (void)type;
	return NULL;
}

CHIAKI_EXPORT ChiakiErrorCode holepunch_session_create_offer(ChiakiHolepunchSession session)
{
	(void)session;
	return CHIAKI_ERR_UNKNOWN;
}
