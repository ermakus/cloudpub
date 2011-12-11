#include <v8.h>
#include <node.h>
#include <string.h>
#include <stdlib.h>
#include <security/pam_appl.h>

#define REQ_FUN_ARG(I, VAR)                                             \
  if (args.Length() <= (I) || !args[I]->IsFunction())                   \
    return ThrowException(Exception::TypeError(                         \
                  String::New("Argument " #I " must be a function")));  \
  Local<Function> VAR = Local<Function>::Cast(args[I]);


struct pam_response *reply;

int null_conv(int num_msg, const struct pam_message **msg, struct pam_response **resp, void *appdata_ptr) {

	*resp = reply;
	return PAM_SUCCESS;

}

static struct pam_conv conv = { null_conv, NULL };

const char* ToCString(const v8::String::Utf8Value& value) {
	return *value ? *value : "<string conversion failed>";
}

extern "C" {
	int _pam_authenticate(const char *service, const char *username, const char *password) {

		pam_handle_t *pamh = NULL;
		int retval = pam_start(service, username, &conv, &pamh);

		if (retval == PAM_SUCCESS) {

			reply = (struct pam_response *) malloc(sizeof(struct pam_response));
			reply[0].resp = (char *) password;
			reply[0].resp_retcode = 0;

			retval = pam_authenticate(pamh, 0);
			pam_end(pamh, PAM_SUCCESS);

		}

		return retval;

	}
}

using namespace node;
using namespace v8;

class PAM:ObjectWrap {

public:

	 static Persistent<FunctionTemplate> s_ct;
	 static void Init(Handle<Object> target) {

		HandleScope scope;

		Local<FunctionTemplate> t = FunctionTemplate::New(New);

		s_ct = Persistent<FunctionTemplate>::New(t);
		s_ct->InstanceTemplate()->SetInternalFieldCount(1);
		s_ct->SetClassName(String::NewSymbol("PAM"));

		NODE_SET_PROTOTYPE_METHOD(s_ct, "authenticate", authenticate);
		target->Set(String::NewSymbol("PAM"), s_ct->GetFunction());

	 }

	 ~PAM() {}

	 static Handle<Value> New(const Arguments& args) {

		HandleScope scope;
		PAM* hw = new PAM();
		hw->Wrap(args.This());
		return args.This();

	 }

	 struct baton_t {
		 PAM *hw;
		 const char *service;
		 const char *username;
		 const char *password;
		 bool result;
		 Persistent<Function> cb;
	 };

	 static Handle<Value> authenticate(const Arguments& args) {

		HandleScope scope;
		REQ_FUN_ARG(3, cb);

		PAM* hw = ObjectWrap::Unwrap<PAM>(args.This());
		baton_t *baton = new baton_t();
		baton->hw = hw;

		String::Utf8Value service(args[0]);
		String::Utf8Value username(args[1]);
		String::Utf8Value password(args[2]);

		baton->service = strdup(ToCString(service));
		baton->username = strdup(ToCString(username));
		baton->password = strdup(ToCString(password));
		baton->cb = Persistent<Function>::New(cb);
		baton->result = false;

		hw->Ref();

		eio_custom(EIO_pam, EIO_PRI_DEFAULT, EIO_AfterPam, baton);
		ev_ref(EV_DEFAULT_UC);

		return Undefined();

	}

	static void EIO_pam(eio_req *req) {

		bool result = false;
		struct baton_t* args = (struct baton_t *) req->data;

		char *service = strdup(args->service);
		char *username = strdup(args->username);
		char *password = strdup(args->password);
		int retval = _pam_authenticate(service, username, password);

		if (retval == PAM_SUCCESS)
			result = true;

		args->result = result;
	 }

	 static int EIO_AfterPam(eio_req *req) {

		HandleScope scope;
		baton_t *baton = static_cast<baton_t *>(req->data);
		ev_unref(EV_DEFAULT_UC);
		baton->hw->Unref();

		Local<Value> argv[1];

		// This doesn't work
		//argv[0] = False();

		// This works, but this is not what we want
		argv[0] = Integer::New(baton->result);

		TryCatch try_catch;

		baton->cb->Call(Context::GetCurrent()->Global(), 1, argv);

		if (try_catch.HasCaught())
			FatalException(try_catch);

		baton->cb.Dispose();

		delete baton;
		return 0;

	 }
};

Persistent<FunctionTemplate> PAM::s_ct;

extern "C" {

	static void init (Handle<Object> target) {
		PAM::Init(target);
	}

	NODE_MODULE(pam, init);
}
