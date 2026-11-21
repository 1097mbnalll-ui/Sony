/* Minimal stand-in for <curl/curl.h>.
 * Tarjuman builds chiaki-ng for LAN Remote Play only, so the PSN/internet
 * code paths that need libcurl are not compiled. Only the opaque type used
 * in private chiaki headers is required. */
#ifndef TRJM_STUB_CURL_H
#define TRJM_STUB_CURL_H
typedef void CURL;
#endif
