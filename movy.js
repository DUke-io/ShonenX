/**
 * Movy (movy.sx) Extension for KuroX / Mangayomi Extension Bridge
 * 
 * Provides automated search, metadata indexing, episode resolution,
 * and decrypted high-speed multi-server streaming (4K, 1080p, 720p, 480p)
 * for Movies, TV Shows, and Anime.
 * 
 * Engine: Mangayomi (JavaScript runtime)
 * ItemType: Anime / Media (itemType: 1, isManga: false)
 * Author: KuroX Team
 */

class DefaultExtension extends MProvider {
    constructor() {
        super();
        this.client = new Client();
        this.tmdbBase = "https://db.wecollege.net/3";
        this.streamApiBase = "https://api.wecollege.net";
        this.imgBase = "https://image.tmdb.org/t/p/w500";
    }

    get supportsLatest() {
        return true;
    }

    getHeaders(url) {
        return {
            "Referer": "https://www.movy.sx/",
            "Origin": "https://www.movy.sx",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        };
    }

    /**
     * Get popular/trending titles
     */
    async getPopular(page) {
        try {
            const pageNum = page || 1;
            const url = `${this.tmdbBase}/trending/all/day?page=${pageNum}`;
            const res = await this.client.get(url, this.getHeaders());
            const data = JSON.parse(res.body);
            const list = (data.results || [])
                .filter(item => item && (item.media_type === 'movie' || item.media_type === 'tv'))
                .map(item => this._mapTmdbItem(item));

            return {
                list: list,
                hasNextPage: (data.page || 1) < (data.total_pages || 1)
            };
        } catch (e) {
            return { list: [], hasNextPage: false };
        }
    }

    /**
     * Get latest releases
     */
    async getLatestUpdates(page) {
        try {
            const pageNum = page || 1;
            const url = `${this.tmdbBase}/movie/now_playing?page=${pageNum}`;
            const res = await this.client.get(url, this.getHeaders());
            const data = JSON.parse(res.body);
            const list = (data.results || [])
                .filter(item => item != null)
                .map(item => this._mapTmdbItem({ ...item, media_type: 'movie' }));

            return {
                list: list,
                hasNextPage: (data.page || 1) < (data.total_pages || 1)
            };
        } catch (e) {
            return { list: [], hasNextPage: false };
        }
    }

    /**
     * Search across Movies, TV Series, and Anime
     */
    async search(query, page, filters) {
        try {
            if (!query || query.trim().length === 0) {
                return this.getPopular(page);
            }
            const pageNum = page || 1;
            const url = `${this.tmdbBase}/search/multi?query=${encodeURIComponent(query.trim())}&page=${pageNum}`;
            const res = await this.client.get(url, this.getHeaders());
            const data = JSON.parse(res.body);
            const list = (data.results || [])
                .filter(item => item && (item.media_type === 'movie' || item.media_type === 'tv'))
                .map(item => this._mapTmdbItem(item));

            return {
                list: list,
                hasNextPage: (data.page || 1) < (data.total_pages || 1)
            };
        } catch (e) {
            return { list: [], hasNextPage: false };
        }
    }

    /**
     * Fetch media details and build the episode tree
     */
    async getDetail(url) {
        try {
            let mediaType = 'movie';
            let id = '';

            if (url.startsWith('{')) {
                const parsed = JSON.parse(url);
                mediaType = parsed.mediaType || 'movie';
                id = String(parsed.tmdbId || parsed.id);
            } else {
                const parts = url.split('/').filter(Boolean);
                mediaType = parts[0] === 'tv' ? 'tv' : 'movie';
                id = parts[1];
            }

            const detailUrl = `${this.tmdbBase}/${mediaType}/${id}?append_to_response=external_ids,credits`;
            const res = await this.client.get(detailUrl, this.getHeaders());
            const data = JSON.parse(res.body);

            const title = data.title || data.name || data.original_title || data.original_name || 'Unknown';
            const year = (data.release_date || data.first_air_date || '').split('-')[0];
            const imdbId = data.external_ids ? data.external_ids.imdb_id : '';
            const genres = (data.genres || []).map(g => g.name);
            const poster = data.poster_path ? `${this.imgBase}${data.poster_path}` : '';
            const overview = data.overview || '';
            const author = (data.credits?.crew || []).find(c => c.job === 'Director')?.name || '';

            const episodes = [];

            if (mediaType === 'movie') {
                episodes.push({
                    name: title,
                    url: JSON.stringify({
                        tmdbId: Number(id),
                        mediaType: 'movie',
                        title: title,
                        year: year,
                        imdbId: imdbId
                    }),
                    dateUpload: data.release_date || '',
                    isFiller: false
                });
            } else {
                // TV series or Anime: populate all seasons and episodes
                const seasons = (data.seasons || []).filter(s => s.season_number > 0);
                for (const s of seasons) {
                    try {
                        const sUrl = `${this.tmdbBase}/tv/${id}/season/${s.season_number}`;
                        const sRes = await this.client.get(sUrl, this.getHeaders());
                        const sData = JSON.parse(sRes.body);
                        for (const ep of (sData.episodes || [])) {
                            episodes.push({
                                name: `S${s.season_number} E${ep.episode_number}${ep.name ? ' - ' + ep.name : ''}`,
                                url: JSON.stringify({
                                    tmdbId: Number(id),
                                    mediaType: 'tv',
                                    title: title,
                                    year: year,
                                    totalSeasons: data.number_of_seasons || seasons.length,
                                    seasonId: s.season_number,
                                    episodeId: ep.episode_number,
                                    imdbId: imdbId
                                }),
                                dateUpload: ep.air_date || '',
                                description: ep.overview || '',
                                isFiller: false
                            });
                        }
                    } catch (_) {}
                }
            }

            return {
                name: title,
                link: url,
                imageUrl: poster,
                description: overview,
                author: author,
                genre: genres,
                status: data.status === 'Ended' ? 1 : 0,
                episodes: episodes
            };
        } catch (e) {
            return {
                name: 'Unavailable',
                link: url,
                imageUrl: '',
                description: '',
                author: '',
                genre: [],
                status: 0,
                episodes: []
            };
        }
    }

    /**
     * Resolves seed, contacts Movy streaming clusters (Miami, Boise),
     * decrypts the payload, and produces ready-to-play HLS video streams.
     */
    async getVideoList(url) {
        let params = {};
        try {
            params = JSON.parse(url);
        } catch (_) {
            return [];
        }

        const tmdbId = Number(params.tmdbId);
        if (!tmdbId) return [];

        // 1. Fetch seed for media ID
        let seed = '';
        try {
            const seedRes = await this.client.get(`${this.streamApiBase}/seed?mediaId=${tmdbId}`, this.getHeaders());
            const seedData = JSON.parse(seedRes.body);
            seed = seedData.seed;
        } catch (e) {
            return [];
        }

        if (!seed) return [];

        // 2. Query Movy streaming clusters
        const servers = [
            { id: 'miami', name: 'Miami (4K/1080p Fast)' },
            { id: 'boise', name: 'Boise (HD Backup)' }
        ];

        const videos = [];

        for (const srv of servers) {
            try {
                const query = {
                    title: params.title || '',
                    mediaType: params.mediaType || 'movie',
                    year: params.year || '',
                    tmdbId: String(tmdbId),
                    enc: '2',
                    seed: seed
                };

                if (params.mediaType === 'tv') {
                    query.seasonId = String(params.seasonId || 1);
                    query.episodeId = String(params.episodeId || 1);
                    query.totalSeasons = String(params.totalSeasons || 1);
                }
                if (params.imdbId) {
                    query.imdbId = params.imdbId;
                }

                const qs = Object.entries(query)
                    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
                    .join('&');

                const streamRes = await this.client.get(`${this.streamApiBase}/${srv.id}/sources?${qs}`, this.getHeaders());
                if (streamRes.statusCode === 200 && streamRes.body) {
                    const decrypted = this._decodePayload(streamRes.body, seed, tmdbId);
                    if (decrypted) {
                        const parsed = JSON.parse(decrypted);
                        const subs = (parsed.subtitles || []).map(sub => ({
                            file: sub.url,
                            label: sub.label || sub.language || 'Sub'
                        }));

                        // Auto multi-bitrate master playlist
                        if (parsed.playlist) {
                            videos.push({
                                url: parsed.playlist,
                                quality: `${srv.name} - Auto (Adaptive)`,
                                originalUrl: parsed.playlist,
                                headers: this.getHeaders(),
                                subtitles: subs
                            });
                        }

                        // Explicit resolution streams (4K, 1080p, 720p, 480p)
                        for (const src of (parsed.sources || [])) {
                            if (src.url) {
                                videos.push({
                                    url: src.url,
                                    quality: `${srv.name} - ${src.quality || 'HD'}`,
                                    originalUrl: src.url,
                                    headers: this.getHeaders(),
                                    subtitles: subs
                                });
                            }
                        }
                    }
                }
            } catch (_) {
                // Continue to backup server
            }
        }

        return videos;
    }

    _mapTmdbItem(item) {
        const title = item.title || item.name || item.original_title || item.original_name || 'Unknown';
        const type = item.media_type === 'tv' ? 'tv' : 'movie';
        return {
            name: title,
            link: `/${type}/${item.id}`,
            imageUrl: item.poster_path ? `${this.imgBase}${item.poster_path}` : '',
            description: item.overview || '',
            status: 1
        };
    }

    /**
     * Movy AES/RC4-derived stream decryption algorithm
     */
    _decodePayload(payload, seed, mediaId) {
        const l = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
        ];
        const magic = [109, 118, 109, 49]; // "mvm1"
        const r = e => (e * (e + 1) & 1) === 0;

        function o(e) {
            e >>>= 0;
            e ^= e >>> 16;
            e = Math.imul(e, 0x85ebca6b) >>> 0;
            e ^= e >>> 13;
            e = Math.imul(e, 0xc2b2ae35) >>> 0;
            return (e ^= e >>> 16) >>> 0;
        }

        function u(e, a) {
            e >>>= 0;
            return (a &= 31) === 0 ? e >>> 0 : (e << a | e >>> 32 - a) >>> 0;
        }

        const b64 = payload.replace(/-/g, "+").replace(/_/g, "/").padEnd(4 * Math.ceil(payload.length / 4), "=");
        const n = (function(str) {
            if (typeof atob === "function") {
                const bin = atob(str);
                const bytes = new Uint8Array(bin.length);
                for (let j = 0; j < bin.length; j++) bytes[j] = bin.charCodeAt(j);
                return bytes;
            }
            return new Uint8Array(globalThis.Buffer.from(str, "base64"));
        })(b64);

        const keyStream = (function(s, mId, len) {
            const state = (function(sd, id) {
                const S = Array(61);
                let st = o((function(sStr) {
                    let h = 0x811c9dc5;
                    for (let t = 0; t < sStr.length; t++) {
                        h = Math.imul(h ^ sStr.charCodeAt(t), 0x1000193) >>> 0;
                    }
                    return o(h);
                })(sd) ^ o(id >>> 0 ^ 0x9e3779b9)) >>> 0;

                for (let e = 0; e < 8; e++) {
                    if (r(e)) {
                        const idx = st % 61;
                        st = u(st + 0x9e3779b9 >>> 0, 7 + (7 & e));
                        S[idx] = (st ^ o(st)) >>> 0;
                        st = o(st + idx >>> 0);
                    } else {
                        S[e] = l[15 & e];
                    }
                }
                return { S: S, acc: o(0xa5a5a5a5 ^ st) >>> 0 };
            })(s, mId);

            const ks = new Uint8Array(len);
            let d = 0;
            for (let e = 0; e < len;) {
                const word = (function(stObj, idx) {
                    const S = stObj.S;
                    let acc = stObj.acc;
                    const slot = acc % 61;
                    const exists = 0 - Number(slot in S);
                    const rVal = S[slot] >>> 0;
                    const c = Math.imul(0x9e3779b9, idx + 1) >>> 0;
                    const b = (((acc ^ (rVal ^ c) >>> 0) >>> 0) | (acc & (rVal ^ c) >>> 0 & exists) >>> 0) >>> 0;
                    acc = o(((u(b + acc >>> 0, 31 & slot) ^ u(acc, 31 & Math.imul(slot, 7))) >>> 0) + 0x9e3779b9 >>> 0);
                    S[slot] = acc >>> 0;
                    stObj.acc = acc;
                    return acc >>> 0;
                })(state, d++);

                ks[e++] = 255 & word;
                if (e < len) ks[e++] = word >>> 8 & 255;
                if (e < len) ks[e++] = word >>> 16 & 255;
                if (e < len) ks[e++] = word >>> 24 & 255;
            }
            return ks;
        })(seed, mediaId, n.length);

        for (let e = 0; e < n.length; e++) {
            n[e] ^= keyStream[e];
        }

        for (let e = 0; e < magic.length; e++) {
            if (n[e] !== magic[e]) return null;
        }

        const bodyBytes = n.subarray(magic.length);
        if (typeof TextDecoder !== "undefined") {
            return new TextDecoder("utf-8").decode(bodyBytes);
        }
        return globalThis.Buffer.from(bodyBytes).toString("utf8");
    }
}
