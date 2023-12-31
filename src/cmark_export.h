#ifndef CMARK_EXPORT_H
#define CMARK_EXPORT_H

#ifdef CMARK_STATIC_DEFINE
#  define CMARK_EXPORT
#  define CMARK_NO_EXPORT
#else
#  ifndef CMARK_EXPORT
#    ifdef cmark_EXPORTS
#      define CMARK_EXPORT __attribute__((visibility("default")))
#    else
#      define CMARK_EXPORT __attribute__((visibility("default")))
#    endif
#  endif

#  ifndef CMARK_NO_EXPORT
#    define CMARK_NO_EXPORT __attribute__((visibility("hidden")))
#  endif
#endif

#ifndef CMARK_DEPRECATED
#  define CMARK_DEPRECATED __attribute__ ((__deprecated__))
#endif

#ifndef CMARK_DEPRECATED_EXPORT
#  define CMARK_DEPRECATED_EXPORT CMARK_EXPORT CMARK_DEPRECATED
#endif

#ifndef CMARK_DEPRECATED_NO_EXPORT
#  define CMARK_DEPRECATED_NO_EXPORT CMARK_NO_EXPORT CMARK_DEPRECATED
#endif

#endif /* CMARK_EXPORT_H */
